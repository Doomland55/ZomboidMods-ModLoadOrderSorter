package zombie.gameStates;

/** Small game API stand-in for the standalone bridge tests. */
public final class ChooseGameInfo {
    public static Mod mod;
    public static Mod getModDetails(String id) { return "test".equals(id) ? mod : null; }
    public static final class Mod {
        private final String common, version;
        public Mod(String common, String version) { this.common = common; this.version = version; }
        public String getCommonDir() { return common; }
        public String getVersionDir() { return version; }
    }
}
