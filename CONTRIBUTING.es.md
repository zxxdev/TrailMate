# Cómo colaborar con TrailMate

[English](CONTRIBUTING.md) · **Español**

Gracias por echar una mano. Los issues y las pull requests se pueden escribir en inglés o en español. TrailMate está en alfa, y lo que más necesita son avisos de otras clases, razas y rangos de nivel.

## Avisar de un problema

Abre un issue con:

1. Qué hiciste y qué esperabas que pasara.
2. La salida de `/tm test`: en el juego, abre la pestaña **Registro** del panel, selecciónalo todo y cópialo. No lleva nombres de personaje ni de cuenta.
3. Una captura si es sobre la flecha, el mapa o una ventana. Recorta el nombre de tu personaje y el chat, por favor.

## Cambiar el código

- `TrailMate/core/` es Lua 5.1 sin la API del juego, y cada cambio ahí va con su test en `spec/`.
- `TrailMate/game/` habla con el juego. Comprueba que cada función del juego existe antes de usarla, porque este cliente es nuevo y no es igual que el clásico ni que el actual.
- `TrailMate/data/` lo generan los scripts de `tools/`. Cambia el script, no los datos.
- El puente (`bridge/`) es Go solo con la biblioteca estándar. No añadas dependencias sin abrir antes un issue, por favor.

Antes de abrir una pull request:

```bash
luacheck .
busted
cd bridge && gofmt -l . && go vet ./... && go test ./...
```

La CI pasa las mismas comprobaciones, y una pull request solo se fusiona cuando pasan.

## Corregir una traducción

Los textos están en inglés en el código; el español está en `TrailMate/core/Locale.lua` y cada uno de los demás idiomas en `TrailMate/core/locales/` (`deDE.lua`, `frFR.lua`, `itIT.lua`, `ptBR.lua`, `ruRU.lua`, `koKR.lua`, `zhCN.lua`, `zhTW.lua`). Esos se tradujeron con IA, así que se agradece la mirada de alguien nativo: cambia el texto de la derecha, deja tal cual la clave en inglés de la izquierda y mantén sus `%s` y `%d` en el mismo orden (lo comprueba una prueba). Un texto que falte en un fichero sale en inglés.

## Las reglas del addon

- **Aconseja, nunca juega.** Nada de pulsar teclas, moverse, comprar, vender ni gastar por el jugador.
- **No depende de ningún otro addon** mientras se juega.
- **El compañero de IA no tiene herramientas.** Solo contesta con texto, y lo que vuelve al juego son datos que el addon comprueba antes de usarlos.
- **Ningún dato personal** en el código, el registro ni lo que guarda el addon, más allá de lo que necesita.
