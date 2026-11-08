import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import me.refri.mlos.ModFilesBridge;
import zombie.gameStates.ChooseGameInfo;

public class ModFilesBridgeTest {
    private static void check(boolean ok) { if (!ok) throw new AssertionError(); }
    private static String await(String id) throws Exception {
        for (int i = 0; i < 1000; i++) {
            String state = ModFilesBridge.state(id);
            if (!state.equals("pending")) return state;
            Thread.sleep(5);
        }
        throw new AssertionError("scan timed out");
    }
    public static void main(String[] args) throws Exception {
        // The distributable must retain exactly the runtime annotations ZombieBuddy scans.
        int globals = 0;
        for (java.lang.reflect.Method method : ModFilesBridge.class.getDeclaredMethods()) {
            se.krka.kahlua.integration.annotations.LuaMethod lua = method.getAnnotation(se.krka.kahlua.integration.annotations.LuaMethod.class);
            if (lua != null && lua.global()) { check(lua.name().startsWith("MLOS_Buddy")); globals++; }
        }
        check(globals == 7);
        Path tmp = Files.createTempDirectory("mlos-bridge-test");
        Path common = tmp.resolve("common"), version = tmp.resolve("42.0");
        Path shared = common.resolve("media/lua/shared/A.lua"), replacement = version.resolve("media/lua/shared/A.lua");
        Path client = version.resolve("media/lua/client/nested/B.lua");
        Files.createDirectories(shared.getParent()); Files.createDirectories(client.getParent());
        Files.createDirectories(replacement.getParent());
        Files.write(shared, "old".getBytes(StandardCharsets.UTF_8));
        Files.write(replacement, "new".getBytes(StandardCharsets.UTF_8));
        Files.write(client, "function X.foo() end\n".getBytes(StandardCharsets.UTF_8));
        ChooseGameInfo.mod = new ChooseGameInfo.Mod(common.toString(), version.toString());
        check(ModFilesBridge.begin("unknown") == null);
        String id = ModFilesBridge.begin("test"); check(id != null); check(await(id).equals("ready"));
        check(ModFilesBridge.count(id) == 2);
        check(ModFilesBridge.path(id, 0).equals("media/lua/client/nested/B.lua"));
        check(ModFilesBridge.path(id, 1).equals("media/lua/shared/A.lua"));
        check(ModFilesBridge.source(id, 1).equals("new"));
        String fingerprint = ModFilesBridge.fingerprint(id); check(fingerprint.length() == 64);
        ModFilesBridge.release(id); check(ModFilesBridge.state(id).equals("error"));
        Files.write(replacement, "NEW".getBytes(StandardCharsets.UTF_8));
        id = ModFilesBridge.begin("test"); check(await(id).equals("ready"));
        check(!fingerprint.equals(ModFilesBridge.fingerprint(id))); ModFilesBridge.release(id);
        ChooseGameInfo.mod = new ChooseGameInfo.Mod(tmp.resolve("missing1").toString(), tmp.resolve("missing2").toString());
        id = ModFilesBridge.begin("test"); check(await(id).equals("error")); ModFilesBridge.release(id);
        ChooseGameInfo.mod = new ChooseGameInfo.Mod(tmp.resolve("missing").toString(), version.toString());
        id = ModFilesBridge.begin("test"); check(await(id).equals("ready")); ModFilesBridge.release(id);
        try {
            Files.createSymbolicLink(client.getParent().resolve("link.lua"), client);
            id = ModFilesBridge.begin("test"); check(await(id).equals("error")); ModFilesBridge.release(id);
        } catch (UnsupportedOperationException | SecurityException e) { /* symlinks unavailable */ }
        System.out.println("Java bridge tests passed");
    }
}
