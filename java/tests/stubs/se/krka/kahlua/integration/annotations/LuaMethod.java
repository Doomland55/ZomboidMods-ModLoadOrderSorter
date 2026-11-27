package se.krka.kahlua.integration.annotations;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
@Retention(RetentionPolicy.RUNTIME)
public @interface LuaMethod { String name(); boolean global(); }
