-- Arrow maths. Pure Lua 5.1.
--
-- Map coordinates go from 0 to 1: x grows to the east, y grows to the south.
-- The player's facing is in radians, 0 is north and it grows counter-clockwise
-- (pi/2 is west). An arrow texture that points up is rotated counter-clockwise
-- by the returned angle.

local _, ns = ...

local Geo = {}
ns.Geo = Geo

local TWO_PI = 2 * math.pi

--- Distance in yards between two points of the same map, given the map size
--- in yards. Returns nil when the size is unknown.
function Geo.distance(px, py, tx, ty, width, height)
  if not (width and height) then
    return nil
  end
  local east, south = (tx - px) * width, (ty - py) * height
  return math.sqrt(east * east + south * south)
end

--- Angle from north to the target, counter-clockwise, in [0, 2pi).
function Geo.bearing(px, py, tx, ty, width, height)
  local east = (tx - px) * (width or 1)
  local south = (ty - py) * (height or 1)
  if east == 0 and south == 0 then
    return nil
  end
  local angle = math.atan2(-east, -south)
  return angle % TWO_PI
end

--- Rotation for an up-pointing arrow so it points at the target, in [0, 2pi).
function Geo.arrowRotation(bearing, facing)
  if not (bearing and facing) then
    return nil
  end
  return (bearing - facing) % TWO_PI
end

--- Which cell of a picture holding the arrow drawn at `frames` angles shows
--- this rotation: 0 to frames - 1, nearest angle.
function Geo.arrowFrame(rotation, frames)
  return math.floor((rotation % TWO_PI) / TWO_PI * frames + 0.5) % frames
end

--- How far off course the target is: 0 straight ahead, 1 straight behind.
function Geo.offCourse(rotation)
  local angle = rotation % TWO_PI
  if angle > math.pi then
    angle = TWO_PI - angle
  end
  return angle / math.pi
end

--- Short text for a distance in yards.
function Geo.formatDistance(yards)
  if not yards then
    return "?"
  end
  if yards >= 1000 then
    return ("%.1f km"):format(yards * 0.9144 / 1000)
  end
  return ("%d m"):format(math.floor(yards * 0.9144 + 0.5))
end
