@tool
extends Node3D

@onready var portal = preload("res://Portal.tscn")
@onready var pool_scene = preload("res://Pool.tscn")

@onready var _rng
var entry
var exits = []
var item_slots = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
  pass # Replace with function body.

func _process(delta: float) -> void:
  pass

func cell_neighbors(grid, pos, id):
  var neighbors = []
  for x in range(-1, 2):
    for z in range(-1, 2):
      # no diagonals
      if x != 0 and z != 0:
        continue
      elif x == 0 and z == 0:
        continue

      var vec = Vector3(pos.x + x, pos.y, pos.z + z)
      var cell_val = grid.get_cell_item(vec)

      if cell_val == id:
        neighbors.append(vec)
  return neighbors

const FLOOR = 0
const WALL = 5
const CEILING = 3
const INTERNAL_HALL = 7
const INTERNAL_HALL_TURN = 6
const MARKER = 8
const BENCH = 9

const DIRECTIONS = [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]

func rand_dir():
  return DIRECTIONS[_rng.randi() % len(DIRECTIONS)]

func vlt(v1, v2):
  return v1 if v1.x < v2.x or v1.z < v2.z else v2

func vgt(v1, v2):
  return v1 if v1.x > v2.x or v1.z > v2.z else v2

func generate(
    grid,
    start_pos,
    min_room_dimension,
    max_room_dimension,
    room_count,
    title,
    prev_title,
  ):
  _rng = RandomNumberGenerator.new()
  _rng.seed = hash(title)

  var rand_dim = func() -> int:
    return _rng.randi_range(min_room_dimension, max_room_dimension)

  # var starting_hall_dir = rand_dir(0)
  var starting_hall = generate_hall(grid, Vector3(1, 0, 0), start_pos, true)
  starting_hall[2].text = prev_title
  grid.set_cell_item(starting_hall[0] + Vector3(0, 1, 0), WALL, 0)

  # reset exported points
  # entry = [start_pos, Vector3(1, 0, 0)]
  entry = starting_hall
  exits = []
  item_slots = []

  var room_width = rand_dim.call()
  var room_length = rand_dim.call()
  var room_center = Vector3(
    starting_hall[0].x + starting_hall[1].x * (2 + room_width / 2),
    start_pos.y,
    starting_hall[0].z + starting_hall[1].z * (1 + room_length / 2),
  )

  var next_room_direction
  var next_room_width
  var next_room_length
  var next_room_center

  var room_list = []
  var branch_point_list = []
  var room_entry

  while len(room_list) < room_count:
    room_entry = {
      "center": room_center,
      "width": room_width,
      "length": room_length
    }
    branch_point_list.append(room_entry)
    room_list.append(room_entry)

    var bounds = room_to_bounds(room_center, room_width, room_length)
    carve_room(grid, bounds[0], bounds[1], start_pos.y)

    var early_terminate = true

    # sometimes just throw in branches to keep em guessing
    if len(branch_point_list) < 3 or _rng.randi() % 4 != 0:
      for nop_ in range(50):
        next_room_direction = rand_dir()
        next_room_width = rand_dim.call()
        next_room_length = rand_dim.call()
        next_room_center = room_center + Vector3(
          next_room_direction.x * (room_width / 2 + next_room_width / 2 + 3),
          0,
          next_room_direction.z * (room_length / 2 + next_room_length / 2 + 3)
        )

        var new_bounds = room_to_bounds(next_room_center, next_room_width, next_room_length)
        if not overlaps_room(grid, new_bounds[0], new_bounds[1], start_pos.y):
          early_terminate = false
          break

    if early_terminate:
      branch_point_list.pop_back()
      var prev_room = branch_point_list.pop_back()
      if prev_room == null:
        break

      room_center = prev_room["center"]
      room_width = prev_room["width"]
      room_length = prev_room["length"]
      continue

    if len(room_list) < room_count:
      var start_hall = vlt(room_center, next_room_center)
      var end_hall = vgt(room_center, next_room_center)
      var hall_width
      var start_hall_offset
      var end_hall_offset

      if (start_hall - end_hall).x != 0:
        hall_width = _rng.randi_range(1, min(room_length, next_room_length))
        start_hall -= Vector3(0, 0, hall_width / 2)
        end_hall += Vector3(0, 0, (hall_width - 1) / 2)
      else:
        hall_width = _rng.randi_range(1, min(room_width, next_room_width))
        start_hall -= Vector3(hall_width / 2, 0, 0)
        end_hall += Vector3((hall_width - 1) / 2, 0, 0)

      carve_room(
          grid,
          start_hall,
          end_hall,
          start_pos.y
      )

    room_center = next_room_center
    room_width = next_room_width
    room_length = next_room_length

  # add the final room
  # TODO: restructure the whole weird-ass loop here
  room_list.append(room_entry)

  # ignore starting hall
  for room in room_list:
    decorate_room(grid, room)

  return [entry, exits]

func decorate_room(grid, room):
  var center = room.center
  var width = room.width
  var length = room.length

  if !Engine.is_editor_hint():
    decorate_room_center(grid, center, width, length)

  var bounds = room_to_bounds(center, width, length)
  var c1 = bounds[0]
  var c2 = bounds[1]
  var y = center.y

  # walk border of room to place wall objects
  for x in range(c1.x, c2.x + 1):
    for z in [c1.z, c2.z]:
      decorate_wall_tile(grid, Vector3(x, y, z))
  for z in range(c1.z, c2.z + 1):
    for x in [c1.x, c2.x]:
      decorate_wall_tile(grid, Vector3(x, y, z))

func decorate_room_center(grid, center, width, length):
  if width > 2 and length > 2 and _rng.randi_range(0, 2) == 0:
    var pool = pool_scene.instantiate()
    var bounds = room_to_bounds(center, width, length)
    var true_center = (bounds[0] + bounds[1]) / 2
    pool.position = true_center * 4
    add_child(pool)
    return

  var bench_area_bounds = null
  var bench_area_ori = 0
  if width > length and width > 2:
    bench_area_bounds = room_to_bounds(center, width - 2, 0)
  elif length > width and length > 2:
    bench_area_ori = vecToOrientation(grid, Vector3(1, 0, 0))
    bench_area_bounds = room_to_bounds(center, 0, length - 2)
  if bench_area_bounds:
    var c1 = bench_area_bounds[0]
    var c2 = bench_area_bounds[1]
    var y = center.y
    for x in range(c1.x, c2.x + 1):
      for z in range(c1.z, c2.z + 1):
        grid.set_cell_item(Vector3(x, y, z), BENCH, bench_area_ori)

  """var light = SpotLight3D.new()
  var bounds = room_to_bounds(center, width, length)
  var truecenter = 4 * ((bounds[0] + bounds[1]) / 2)

  light.position = truecenter + Vector3(0, 7, 0)
  light.rotation.x = 3 * PI / 2
  light.spot_range = 17 + min(width, length)
  light.spot_attenuation = 0.5
  light.light_energy = 5
  light.light_color = Color(_rng.randf(), _rng.randf(), _rng.randf())
  add_child(light)"""

func vecToRot(vec):
  if vec.z < 0:
    return 0.0
  elif vec.z > 0:
    return PI
  elif vec.x > 0:
    return 3 * PI / 2
  elif vec.x < 0:
    return PI / 2
  return 0.0

func vecToOrientation(grid, vec):
  var vec_basis = Basis.looking_at(vec.normalized())
  return grid.get_orthogonal_index_from_basis(vec_basis)

func decorate_wall_tile(grid, pos):
  # grid.set_cell_item(pos + Vector3(0, 2, 0), MARKER, 0)

  var wall_neighbors = cell_neighbors(grid, pos, WALL)
  for wall in wall_neighbors:
    var slot = (wall + pos) / 2
    var hall_dir = wall - pos
    var hall_corner = wall + hall_dir

    # put an exit everywhere it fits
    if (
        grid.get_cell_item(hall_corner - Vector3(0, 1, 0)) != FLOOR and
        len(cell_neighbors(grid, hall_corner - Vector3(0, 1, 0), FLOOR)) == 0
    ):
      var hall = generate_hall(grid, hall_dir, wall)
      exits.append(hall)
    # put exhibit items everywhere else
    else:
      var is_dupe = false
      for item_slot in item_slots:
        if item_slot[0].is_equal_approx(slot):
          is_dupe = true
      if not is_dupe:
        item_slots.append([slot, hall_dir])

func generate_hall(grid, hall_dir, hall_start, label_at_end=false):
  var ori = vecToOrientation(grid, hall_dir)
  var hall_corner = hall_start + hall_dir

  grid.set_cell_item(hall_start, INTERNAL_HALL, ori)
  grid.set_cell_item(hall_start - Vector3(0, 1, 0), FLOOR, 0)
  grid.set_cell_item(hall_corner, INTERNAL_HALL_TURN, ori)
  grid.set_cell_item(hall_corner - Vector3(0, 1, 0), FLOOR, 0)

  var exit_hall_dir = hall_dir.rotated(Vector3(0, 1, 0), 3 * PI / 2)
  # var exit_hall_dir = Vector3(0, 0, 1)
  var exit_hall = hall_corner + exit_hall_dir
  var exit_ori = vecToOrientation(grid, exit_hall_dir)
  grid.set_cell_item(exit_hall, INTERNAL_HALL, exit_ori)
  grid.set_cell_item(exit_hall - Vector3(0, 1, 0), FLOOR, 0)

  var label = Label3D.new()
  if label_at_end:
    label.position = 4 * (exit_hall + exit_hall_dir * 0.51) + Vector3(0, 3.5, 0)
    label.rotation.y = vecToRot(exit_hall_dir) + PI
    label.text = ""
  else:
    label.position = 4 * (hall_start - hall_dir * 0.51) + Vector3(0, 3.5, 0)
    label.rotation.y = vecToRot(hall_dir)
    label.text = ""
  add_child(label)

  return [exit_hall, exit_hall_dir, label]

func room_to_bounds(center, width, length):
  return [
    Vector3(center.x - width / 2, center.y, center.z - length / 2),
    Vector3(center.x + width / 2 + width % 2, center.y, center.z + length / 2 + length % 2)
  ]

func carve_room(grid, corner1, corner2, y):
  var lx = corner1.x
  var gx = corner2.x
  var lz = corner1.z
  var gz = corner2.z
  for x in range(lx - 1, gx + 2):
    for z in range(lz - 1, gz + 2):
      if x < lx or z < lz or x > gx or z > gz:
        if grid.get_cell_item(Vector3(x, y - 1, z)) != FLOOR:
          grid.set_cell_item(Vector3(x, y, z), WALL, 0)
          grid.set_cell_item(Vector3(x, y + 1, z), WALL, 0)
          grid.set_cell_item(Vector3(x, y + 2, z), -1, 0)
      else:
        grid.set_cell_item(Vector3(x, y, z), -1, 0)
        grid.set_cell_item(Vector3(x, y + 1, z), -1, 0)
        grid.set_cell_item(Vector3(x, y + 2, z), CEILING, 0)
        grid.set_cell_item(Vector3(x, y - 1, z), FLOOR, 0)

func overlaps_room(grid, corner1, corner2, y):
  for x in range(corner1.x - 1, corner2.x + 2):
    for z in range(corner1.z - 1, corner2.z + 2):
      var cell = grid.get_cell_item(Vector3(x, y - 1, z))
      if cell == FLOOR:
        return true
  return false
