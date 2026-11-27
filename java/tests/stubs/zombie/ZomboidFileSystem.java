package zombie;
import java.util.ArrayList;
import java.util.List;
public class ZomboidFileSystem {
    public static ZomboidFileSystem instance = new ZomboidFileSystem();
    public final List<String> roots = new ArrayList<String>();
    public final List<String> known = new ArrayList<String>();
    public String cacheDir;
    public void getInstalledItemModsFolders(List<String> out) { out.addAll(roots); }
    public void getStagedItemModsFolders(List<String> out) { }
    public void getAllModFolders(List<String> out) { out.addAll(known); }
    public String getCacheDirSub(String path) { return cacheDir; }
}
