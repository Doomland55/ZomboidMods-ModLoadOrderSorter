package me.refri.mlos;
import java.nio.file.*;
import java.io.IOException;
import java.util.*;

public class ModFilesTest {
    private static void check(boolean v, String message) { if (!v) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        Path tmp = Files.createTempDirectory("mlos-test");
        try {
            Path mods = Files.createDirectory(tmp.resolve("mods"));
            Path mod = Files.createDirectory(mods.resolve("mod"));
            Path nested = Files.createDirectories(mod.resolve("common/media/lua/client/deep"));
            Files.write(nested.resolve("a.lua"), new byte[] {1});
            List<String> roots = Arrays.asList(mods.toString());
            List<String> known = Arrays.asList(mod.toString());
            check(ModFiles.listValidated(mod, roots, known).equals(Arrays.asList("common/media/lua/client/deep/a.lua")), "recursive listing");
            zombie.ZomboidFileSystem.instance.roots.add(mods.toString());
            zombie.ZomboidFileSystem.instance.known.add(mod.toString());
            zombie.ZomboidFileSystem.instance.cacheDir = mods.toString();
            zombie.gameStates.ChooseGameInfo.current = new zombie.gameStates.ChooseGameInfo.Mod("test", mod.toString());
            check(ModFiles.listModFiles("test").size() == 1, "public API");
            check(ModFiles.listModFiles("other") == null, "mismatched id");
            check(ModFiles.listValidated(mod, roots, Collections.<String>emptyList()) == null, "unregistered mod");
            check(ModFiles.listValidated(mod.resolve("../mod"), roots, known) == null, "relative traversal");
            check(ModFiles.listValidated(tmp, roots, Arrays.asList(tmp.toString())) == null, "outside root");
            check(ModFiles.listModFiles("../outside") == null, "invalid id");
            try {
                Files.createSymbolicLink(mod.resolve("escape"), tmp);
                boolean rejected = false;
                try { ModFiles.listValidated(mod, roots, known); } catch (IOException ex) { rejected = true; }
                check(rejected, "symlink must be rejected");
            } catch (UnsupportedOperationException | SecurityException ex) {
                System.out.println("Symlink test skipped: " + ex);
            }
            System.out.println("Java mod file listing tests passed");
        } finally {
            Files.walkFileTree(tmp, new SimpleFileVisitor<Path>() {
                public FileVisitResult visitFile(Path file, java.nio.file.attribute.BasicFileAttributes attrs) throws IOException { Files.delete(file); return FileVisitResult.CONTINUE; }
                public FileVisitResult postVisitDirectory(Path dir, IOException error) throws IOException { if (error != null) throw error; Files.delete(dir); return FileVisitResult.CONTINUE; }
            });
        }
    }
}
