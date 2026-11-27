package me.refri.mlos;

import java.io.IOException;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import se.krka.kahlua.integration.annotations.LuaMethod;
import zombie.ZomboidFileSystem;
import zombie.gameStates.ChooseGameInfo;

/** Read-only recursive mod file listing. All Lua business logic stays in Lua. */
public final class ModFiles {
    private ModFiles() { }

    /** Returns root-relative paths, or null if validation or enumeration failed. */
    @LuaMethod(name = "MLOS_listModFiles", global = true)
    public static ArrayList<String> listModFiles(String modId) {
        if (!validModId(modId)) return null;
        try {
            ChooseGameInfo.Mod mod = ChooseGameInfo.getModDetails(modId);
            if (mod == null || !modId.equals(mod.getId()) || mod.getDir() == null) return null;
            ArrayList<String> roots = new ArrayList<String>();
            ZomboidFileSystem.instance.getInstalledItemModsFolders(roots);
            ZomboidFileSystem.instance.getStagedItemModsFolders(roots);
            roots.add(ZomboidFileSystem.instance.getCacheDirSub("mods"));
            ArrayList<String> known = new ArrayList<String>();
            ZomboidFileSystem.instance.getAllModFolders(known);
            return listValidated(Paths.get(mod.getDir()), roots, known);
        } catch (IOException | SecurityException | IllegalArgumentException ex) {
            System.out.println("[MLOS] Cannot enumerate mod files for " + modId + ": " + ex);
            return null;
        }
    }

    private static boolean validModId(String id) {
        return id != null && !id.trim().isEmpty() && !id.contains("..")
            && id.indexOf('/') < 0 && id.indexOf('\\') < 0 && id.indexOf(':') < 0
            && id.indexOf('\0') < 0 && id.indexOf('\n') < 0 && id.indexOf('\r') < 0;
    }

    /* Roots are supplied by PZ, not by Lua. Only a registered direct child of
       one of those roots may be inspected, including Workshop library roots. */
    static ArrayList<String> listValidated(Path input, List<String> roots, List<String> known) throws IOException {
        if (input == null || !input.isAbsolute()) return null;
        Path mod = input.normalize();
        if (!input.equals(mod) || Files.isSymbolicLink(mod)
                || !Files.isDirectory(mod, LinkOption.NOFOLLOW_LINKS)) return null;
        boolean registered = false;
        for (String candidate : known) {
            if (candidate != null && mod.equals(Paths.get(candidate).toAbsolutePath().normalize())) {
                registered = true;
                break;
            }
        }
        if (!registered || !isAllowedChild(mod, roots)) return null;
        final Path realRoot = mod.toRealPath();
        final ArrayList<String> result = new ArrayList<String>();
        Files.walkFileTree(mod, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
                ensureInside(dir, realRoot);
                return FileVisitResult.CONTINUE;
            }
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                if (attrs.isSymbolicLink()) throw new IOException("Symbolic link in mod directory: " + file);
                if (attrs.isRegularFile()) {
                    ensureInside(file, realRoot);
                    String relative = mod.relativize(file).toString().replace('\\', '/');
                    if (relative.indexOf('\n') >= 0 || relative.indexOf('\r') >= 0) {
                        throw new IOException("Unsupported filename in mod directory");
                    }
                    result.add(relative);
                }
                return FileVisitResult.CONTINUE;
            }
        });
        Collections.sort(result);
        return result;
    }

    private static boolean isAllowedChild(Path mod, List<String> roots) throws IOException {
        for (String rootString : roots) {
            if (rootString == null) continue;
            Path root = Paths.get(rootString).toAbsolutePath().normalize();
            if (root.equals(mod.getParent()) && Files.isDirectory(root)) {
                return mod.toRealPath().getParent().equals(root.toRealPath());
            }
        }
        return false;
    }

    private static void ensureInside(Path path, Path root) throws IOException {
        if (Files.isSymbolicLink(path) || !path.toRealPath().startsWith(root)) {
            throw new IOException("Path outside mod directory: " + path);
        }
    }
}
