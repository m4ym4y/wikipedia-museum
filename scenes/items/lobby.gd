extends Node3D

@onready var hall_scene = preload("res://scenes/Hall.tscn")
@onready var _grid = $GridMap
@onready var exits = []

const FLOOR_WOOD = 0
const INTERNAL_HALL = 7
const DIRECTIONS = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]

func _get_hall_dir(pos):
	var p = pos - Vector3.UP
	for dir in DIRECTIONS:
		var cell = p + dir
		if _grid.get_cell_item(cell) == FLOOR_WOOD:
			return -dir

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for cell_pos in _grid.get_used_cells():
		var c = Vector3(cell_pos)
		if _grid.get_cell_item(c) == INTERNAL_HALL:
			var hall_dir = _get_hall_dir(c)
			if not hall_dir:
				continue
			var hall = hall_scene.instantiate()
			add_child(hall)
			hall.init(_grid, "$Lobby", "$Lobby", c, hall_dir)
			exits.append(hall)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass