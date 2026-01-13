TalentImporter: встраивание в FrameXML (WoW 3.3.5a)

Почему так:
- FrameXML.toc обычно включает только *.xml.
- Lua нужно подключать через XML: <Script file="..."/>.

Что положить в patch-*.MPQ:
1) Interface\FrameXML\TalentImporter.lua
2) Interface\FrameXML\TalentImporter.xml

Что добавить в Interface\FrameXML\FrameXML.toc:
- добавь строку (в конец или рядом с другими кастомными):
  TalentImporter.xml

Проверка:
- В списке AddOns TalentImporter НЕ появится (он встроен).
- Открой таланты → иконка импорта слева от крестика.

Откат:
- Удали строку TalentImporter.xml из FrameXML.toc и/или удали два файла из MPQ.
