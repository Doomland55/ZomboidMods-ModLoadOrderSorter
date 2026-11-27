package zombie.gameStates;
public class ChooseGameInfo {
    public static Mod current;
    public static Mod getModDetails(String id) { return current; }
    public static class Mod {
        public final String id, dir;
        public Mod(String id, String dir) { this.id = id; this.dir = dir; }
        public String getId() { return id; }
        public String getDir() { return dir; }
    }
}
