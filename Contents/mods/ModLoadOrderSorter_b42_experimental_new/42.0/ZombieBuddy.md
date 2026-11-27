# Опциональное расширение ZombieBuddy

ZombieBuddy **не обязателен**. С ним расширение предоставляет Lua одну функцию
`MLOS_listModFiles(modId)`: она возвращает Java `ArrayList` относительных путей
файлов мода или `nil` при ошибке. Если расширение отсутствует или его загрузка
не разрешена, мод использует данные загруженных Lua-файлов и предупреждает о
неполном анализе.

Функция не принимает пути от Lua, не читает содержимое и ничего не записывает.
Она разрешает только зарегистрированные игрой моды в локальных, Workshop и
staged-каталогах игры. При обнаружении симлинков или ошибке доступа обход
считается неуспешным. Результат перечисляет все обычные файлы; Lua выбирает
`media/lua` в актуальных `common` и версии и читает их через `getModFileReader`.

**Ограничения:** перечисление одного мода синхронно и может задержать кадр;
между модами и файлами анализ уступает управление через `CoroutineManager`.
При конкурентной замене файлов другими процессами между перечислением и чтением
полную защиту от гонок на уровне Lua и Java гарантировать нельзя. Java-модуль
не является песочницей для других модов или процессов.

## Сборка

Исходник: `java/src/main/java/me/refri/mlos/ModFiles.java` в корне репозитория.
Для повторной сборки необходим JDK и classpath Java-классов PZ B42.22, включая
Kahlua. Из корня репозитория:

```sh
PZ_CLASSPATH=/path/to/PZ/Java ./java/build.sh
```

`PZ_CLASSPATH` имеет обычный для платформы формат Java classpath (каталоги и
JAR через `:` на Linux/macOS, `;` на Windows). Игровые классы не включаются в
собранный JAR. ZombieBuddy может запросить подтверждение его загрузки; после
установки или обновления расширения может потребоваться полный перезапуск игры.

For English: the bridge is optional and exports `MLOS_listModFiles(modId)`.
It lists files without following symlinks and does not read file contents. On
failure or without ZombieBuddy the Lua layer uses its limited fallback. A single
mod's traversal is synchronous. See the build instructions above.
