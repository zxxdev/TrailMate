-- Strings shown to the player. Keys are the English text; esES overrides.
-- Missing keys fall back to the key itself. Pure Lua 5.1.

local _, ns = ...

local esES = {
  ["Turn in: "] = "Entregar: ",
  ["Do: "] = "Hacer: ",
  ["Quest log"] = "Diario de misiones",
  ["Needs level %d"] = "Necesita nivel %d",
  ["Not available yet"] = "Aún no disponible",
  ["Tracking: you chose to skip it"] = "Rastreo: elegiste saltártelo",
  ["Not enough gold after your reserve"] = "No llega el oro sin tocar tu reserva",
  ["Useful now and affordable"] = "Útil ya y te lo puedes permitir",
  ["On your keep list"] = "Está en tu lista de guardar",
  ["Quest item"] = "Objeto de misión",
  ["Junk"] = "Basura",
  ["No vendor value"] = "No se puede vender",
  ["Consumable"] = "Consumible",
  ["Unbound green or better: usually worth more at the auction house"] =
    "Verde o mejor sin ligar: suele valer más en la subasta",
  ["Lower item level than what you wear (rough guide)"] = "Menor nivel de objeto que lo que llevas (orientativo)",
  ["Possible upgrade: check it"] = "Puede ser una mejora: míralo",
  ["Trade goods sell well at the auction house"] = "Los materiales se venden bien en la subasta",
  ["No rule for this item: your call"] = "Sin regla para este objeto: tú decides",
  ["Class %s, level %s"] = "Clase %s, nivel %s",
  ["XP %d%%"] = "Experiencia %d%%",
  ["Gold %s"] = "Oro %s",
  ["Map %d at %s, %s"] = "Mapa %d en %s, %s",
  ["Quests in log: %d"] = "Misiones en el diario: %d",
  ["Bag slots free: %d of %d"] = "Huecos libres: %d de %d",
  ["learn"] = "aprende",
  ["skip"] = "sáltalo",
  ["later"] = "más tarde",
  ["sell"] = "vende",
  ["keep"] = "guarda",
  ["auction"] = "subasta",
  ["Trainer advice"] = "Consejo del instructor",
  ["Total to learn now: %s"] = "Total por aprender ahora: %s",
  ["Nothing new to learn here."] = "Nada nuevo que aprender aquí.",
  ["Vendor advice"] = "Consejo para el vendedor",
  ["Sell for about %s: %s"] = "Vende por unos %s: %s",
  ["Nothing to sell."] = "Nada que vender.",
  ["Worth taking to the auction house: %s"] = "Para la subasta: %s",
  ["Bags almost full (%d free): time to go back to a vendor."] =
    "Bolsas casi llenas (%d libres): toca volver a vender.",
  ["Plan finished."] = "Plan terminado.",
  ["No plan loaded. Type /tm questlog to build one from your quest log."] =
    "No hay plan. Escribe /tm diario para crear uno con tu diario de misiones.",
  ["Your quest log is empty."] = "Tu diario de misiones está vacío.",
  ["Plan loaded: %s (%d steps)."] = "Plan cargado: %s (%d pasos).",
  ["Plan rejected: %s"] = "Plan rechazado: %s",
  ["Skipped: %s"] = "Saltado: %s",
  ["Marked as done: %s"] = "Marcado como hecho: %s",
  ["Undone."] = "Deshecho.",
  ["Nothing to undo."] = "Nada que deshacer.",
  ["Step %d of %d"] = "Paso %d de %d",
  ["Arrow: %s"] = "Flecha: %s",
  ["no arrow available"] = "sin flecha disponible",
  ["Tracking spells: %s"] = "Rastreos: %s",
  ["Reserve set to %s."] = "Reserva fijada en %s.",
  ["Commands"] = "Órdenes",
  ["Pick up: "] = "Coger: ",
  ["Type /tm find trainer and the arrow takes you there."] = "Escribe /tm buscar instructor y la flecha te lleva.",
  ["Finding trainers needs the QuestieDB addon."] = "Para buscar instructores hace falta el addon QuestieDB.",
  ["No trainer of your class found in the data."] = "No hay ningún instructor de tu clase en los datos.",
  ["Trainer: %s"] = "Instructor: %s",
  ["Arrow to the nearest trainer of your class"] = "Flecha al instructor de tu clase más cercano",
  ["Arrow back to the plan"] = "La flecha vuelve al plan",
  ["Route: %s, %d steps."] = "Ruta: %s, %d pasos.",
  ["Not now: %s"] = "Ahora no: %s",
  ["Consider abandoning: %s"] = "Plantéate abandonar: %s",
  ["Later: %s"] = "Después: %s",
  ["Nothing worth doing in your quest log right now."] = "Ahora mismo no hay nada que merezca la pena en tu diario.",
  ["Unknown place"] = "Lugar desconocido",
  ["Too hard for now (level %s)"] = "Demasiado difícil por ahora (nivel %s)",
  ["Group or elite quest"] = "Misión de grupo o élite",
  ["Gives little XP now (level %s)"] = "Ya da poca experiencia (nivel %s)",
  ["Hard (level %s): be careful or bring help"] = "Difícil (nivel %s): con cuidado o con ayuda",
  ["You chose to ignore it"] = "Elegiste ignorarlo",
  ["In %s"] = "En %s",
  ["Position unknown here"] = "Aquí no se conoce la posición",
  ["You are there"] = "Has llegado",
  ["Not interested in one? /tm ignore <number>. Already learned? /tm learned <number>."] =
    "¿Alguno no te interesa? /tm ignorar <número>. ¿Ya lo tienes? /tm aprendido <número>.",
  ["Which one? Use the number from the trainer list or the spell name."] =
    "¿Cuál? Usa el número de la lista del instructor o el nombre del hechizo.",
  ["Ignored: %s. It will not be recommended again."] = "Ignorado: %s. No se volverá a recomendar.",
  ["%s will be recommended again."] = "%s se volverá a recomendar.",
  ["Not in your ignored list."] = "No está en tu lista de ignorados.",
  ["Marked as learned: %s"] = "Marcado como aprendido: %s",
  ["Level %d: your trainer now has %s."] = "Nivel %d: tu instructor ya tiene %s.",
  ["Never recommend that spell again (all ranks)"] = "No recomendar más ese hechizo (todos los rangos)",
  ["Stop reminding a spell you already have"] = "Dejar de recordar un hechizo que ya tienes",
  ["Recommend an ignored spell again"] = "Volver a recomendar un hechizo ignorado",
  ["List ignored spells"] = "Lista de hechizos ignorados",
  ["Show or hide the arrow"] = "Muestra u oculta la flecha",
  ["Rebuild the plan by itself when it ends"] = "Rehacer el plan solo cuando se acaba",
  ["Build a plan from your quest log"] = "Crea un plan con tu diario de misiones",
  ["Skip the current step"] = "Salta el paso actual",
  ["Mark the current step as done"] = "Marca el paso actual como hecho",
  ["Undo the last mark"] = "Deshace la última marca",
  ["Advice at the open trainer"] = "Consejo en el instructor abierto",
  ["What to sell, keep or auction"] = "Qué vender, guardar o subastar",
  ["Character summary"] = "Resumen del personaje",
  ["Skip hunter tracking spells"] = "Saltar los rastreos del cazador",
  ["Gold the trainer advice never spends"] = "Oro que el consejo del instructor nunca gasta",
  ["Show or hide the window"] = "Muestra u oculta la ventana",
  ["Remove the plan"] = "Quita el plan",
  ["What this client exposes (for bug reports)"] = "Qué ofrece este cliente (para informar de fallos)",
}

local L = setmetatable({}, {
  __index = function(_, key)
    return key
  end,
})

--- Fills ns.L for the given locale ("esES", "enUS", ...).
function ns.setLocale(locale)
  for k in pairs(L) do
    L[k] = nil
  end
  if locale == "esES" or locale == "esMX" then
    for k, v in pairs(esES) do
      L[k] = v
    end
  end
end

ns.L = L

--- Formats copper as "1g 2s 3c".
function ns.formatMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) % 100
  local c = copper % 100
  if g > 0 then
    return ("%dg %ds %dc"):format(g, s, c)
  elseif s > 0 then
    return ("%ds %dc"):format(s, c)
  end
  return ("%dc"):format(c)
end
