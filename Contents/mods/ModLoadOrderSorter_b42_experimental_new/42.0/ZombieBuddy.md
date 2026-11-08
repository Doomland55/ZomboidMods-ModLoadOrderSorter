# Optional ZombieBuddy integration / Необязательная интеграция с ZombieBuddy

**RU**

Java-модуль входит в состав мода, но ZombieBuddy не является обязательной зависимостью. Чтобы анализировать вновь включённые моды без перезапуска игры, установите [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy) согласно его инструкции, включите этот мод и разрешите загрузку `MLOSBridge.jar`, если ZombieBuddy запросит разрешение. При первом включении или обновлении Java-модуля может потребоваться перезапустить игру: ZombieBuddy загружает JAR при загрузке модов. После загрузки модуля новые включённые моды анализируются без перезапуска.

Без загруженного или разрешённого Java-модуля работает прежний Lua-анализатор и предупреждение о необходимости перезапуска. Оба режима используют один и тот же файл кэша; Java дополнительно сохраняет контрольную сумму содержимого. При ошибке чтения отдельного мода используются доступные данные старого алгоритма, а результат помечается неполным. Причина ошибки выводится в журнал. Модуль не следует символическим ссылкам внутри `media/lua`; он ограничивает размер файла 16 МиБ, а суммарный размер Lua-файлов одного мода — 128 МиБ.

**EN**

The Java bridge is included but ZombieBuddy is optional. To analyse newly enabled mods without restarting, install [ZombieBuddy](https://github.com/zed-0xff/ZombieBuddy) following its instructions, enable this mod, and approve `MLOSBridge.jar` if prompted. Initial activation or an update of the bridge may require a game restart: ZombieBuddy loads Java modules during mod loading. Once the bridge is loaded, newly enabled mods can be analysed without restarting.

If the Java bridge is unavailable or not approved, the original Lua analysis and restart warning remain in use. Both modes share the same cache; Java additionally stores a content fingerprint. If a mod cannot be read, available legacy data is used and the result is marked incomplete; details are logged. The bridge does not follow symlinks inside `media/lua`, and limits a single file to 16 MiB and the combined Lua files of one mod to 128 MiB.
