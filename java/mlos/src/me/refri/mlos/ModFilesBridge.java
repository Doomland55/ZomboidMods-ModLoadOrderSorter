package me.refri.mlos;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicLong;
import se.krka.kahlua.integration.annotations.LuaMethod;

/** ZombieBuddy bridge. No game APIs are called from the worker thread. */
public final class ModFilesBridge {
    private static final long MAX_FILE = 16L * 1024 * 1024;
    private static final long MAX_TOTAL = 128L * 1024 * 1024;
    private static final AtomicLong NEXT = new AtomicLong();
    private static final Map<String, Job> JOBS = new ConcurrentHashMap<>();
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "MLOS-file-scan");
        t.setDaemon(true);
        return t;
    });

    private static final class Job {
        volatile String state = "pending";
        volatile String fingerprint;
        volatile List<String> paths;
        volatile List<String> sources;
        volatile Future<?> future;
    }

    /** Only resolve directories via the game's mod registry, never arbitrary Lua paths. */
    @LuaMethod(name = "MLOS_BuddyBegin", global = true)
    public static String begin(String modId) {
        try {
            Class<?> info = Class.forName("zombie.gameStates.ChooseGameInfo");
            Object mod = info.getMethod("getModDetails", String.class).invoke(null, modId);
            if (mod == null) return null;
            Method version = mod.getClass().getMethod("getVersionDir");
            Method common = mod.getClass().getMethod("getCommonDir");
            String versionDir = (String) version.invoke(mod);
            String commonDir = (String) common.invoke(mod);
            if (versionDir == null || commonDir == null) return null;
            final Job job = new Job();
            String id = Long.toString(NEXT.incrementAndGet());
            JOBS.put(id, job);
            job.future = WORKER.submit(() -> scan(job, versionDir, commonDir));
            return id;
        } catch (Exception | LinkageError e) {
            System.err.println("[MLOS] ZombieBuddy bridge cannot resolve mod " + modId + ": " + e);
            return null;
        }
    }

    private static void collect(String root, TreeMap<String, Path> files) throws IOException {
        Path rootPath = Paths.get(root);
        if (Files.notExists(rootPath, LinkOption.NOFOLLOW_LINKS)) return;
        Path base = rootPath.toRealPath();
        Path lua = base.resolve("media").resolve("lua");
        if (Files.notExists(lua, LinkOption.NOFOLLOW_LINKS)) return;
        if (!Files.isDirectory(lua, LinkOption.NOFOLLOW_LINKS) || !lua.toRealPath().startsWith(base))
            throw new IOException("Invalid media/lua directory: " + lua);
        Files.walkFileTree(lua, new SimpleFileVisitor<Path>() {
            @Override public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Scan cancelled");
                return FileVisitResult.CONTINUE;
            }
            @Override public FileVisitResult visitFile(Path path, BasicFileAttributes attrs) throws IOException {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Scan cancelled");
                if (attrs.isSymbolicLink()) throw new IOException("Symlink in Lua directory: " + path);
                if (attrs.isRegularFile() && path.getFileName().toString().endsWith(".lua")) {
                    String relative = base.relativize(path).toString().replace('\\', '/');
                    files.put(relative, path);
                }
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private static void scan(Job job, String versionDir, String commonDir) {
        try {
            TreeMap<String, Path> files = new TreeMap<>();
            if (Files.notExists(Paths.get(commonDir)) && Files.notExists(Paths.get(versionDir)))
                throw new IOException("Both mod roots are missing");
            collect(commonDir, files);
            collect(versionDir, files); // PZ's getModFileReader prefers the version file.
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            List<String> paths = new ArrayList<>();
            List<String> sources = new ArrayList<>();
            long total = 0;
            for (Map.Entry<String, Path> entry : files.entrySet()) {
                if (Thread.currentThread().isInterrupted()) throw new IOException("Scan cancelled");
                BasicFileAttributes attrs = Files.readAttributes(entry.getValue(), BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
                long size = attrs.size();
                if (!attrs.isRegularFile() || size > MAX_FILE || total + size > MAX_TOTAL)
                    throw new IOException("Invalid or oversized Lua file: " + entry.getKey());
                ByteArrayOutputStream output = new ByteArrayOutputStream((int) size);
                try (InputStream input = Files.newInputStream(entry.getValue(), LinkOption.NOFOLLOW_LINKS)) {
                    byte[] buffer = new byte[8192];
                    int n;
                    while ((n = input.read(buffer)) != -1) {
                        if (Thread.currentThread().isInterrupted()) throw new IOException("Scan cancelled");
                        if (output.size() + (long) n > MAX_FILE || total + output.size() + n > MAX_TOTAL)
                            throw new IOException("Lua scan size limit exceeded");
                        output.write(buffer, 0, n);
                    }
                }
                byte[] bytes = output.toByteArray();
                BasicFileAttributes after = Files.readAttributes(entry.getValue(), BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
                if (bytes.length != size || !after.isRegularFile() || after.size() != size
                        || !after.lastModifiedTime().equals(attrs.lastModifiedTime())
                        || (attrs.fileKey() != null && !attrs.fileKey().equals(after.fileKey())))
                    throw new IOException("File changed while scanning: " + entry.getKey());
                total += bytes.length;
                byte[] name = entry.getKey().getBytes(StandardCharsets.UTF_8);
                digest.update(name);
                digest.update((byte) 0);
                digest.update(bytes);
                digest.update((byte) 0);
                paths.add(entry.getKey());
                sources.add(new String(bytes, StandardCharsets.UTF_8));
            }
            StringBuilder fingerprint = new StringBuilder();
            for (byte b : digest.digest()) fingerprint.append(String.format("%02x", b & 0xff));
            job.paths = paths;
            job.sources = sources;
            job.fingerprint = fingerprint.toString();
            job.state = "ready"; // volatile publication after the snapshot is complete
        } catch (Exception e) {
            System.err.println("[MLOS] ZombieBuddy scan failed: " + e);
            job.state = "error";
        }
    }

    @LuaMethod(name = "MLOS_BuddyState", global = true)
    public static String state(String id) {
        Job job = JOBS.get(id);
        return job == null ? "error" : job.state;
    }

    @LuaMethod(name = "MLOS_BuddyCount", global = true)
    public static double count(String id) {
        Job job = JOBS.get(id);
        return job == null || job.paths == null ? -1 : job.paths.size();
    }

    @LuaMethod(name = "MLOS_BuddyPath", global = true)
    public static String path(String id, double index) {
        Job job = JOBS.get(id);
        int i = (int) index;
        return job == null || job.paths == null || i < 0 || i >= job.paths.size() ? null : job.paths.get(i);
    }

    @LuaMethod(name = "MLOS_BuddySource", global = true)
    public static String source(String id, double index) {
        Job job = JOBS.get(id);
        int i = (int) index;
        return job == null || job.sources == null || i < 0 || i >= job.sources.size() ? null : job.sources.get(i);
    }

    @LuaMethod(name = "MLOS_BuddyFingerprint", global = true)
    public static String fingerprint(String id) {
        Job job = JOBS.get(id);
        return job == null ? null : job.fingerprint;
    }

    @LuaMethod(name = "MLOS_BuddyRelease", global = true)
    public static void release(String id) {
        Job job = JOBS.remove(id);
        if (job != null && job.future != null) job.future.cancel(true);
    }
}
