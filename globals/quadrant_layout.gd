class_name QuadrantLayout
extends RefCounted

const CARD_WIDTH_RATIO: float = 0.34
const CARD_MAX_HEIGHT_RATIO: float = 0.34
const CARD_ASPECT_RATIO: float = 16.0 / 9.0
const HORIZONTAL_GAP: float = 32.0
const VERTICAL_GAP: float = 24.0

static func get_card_size(viewport_size: Vector2) -> Vector2:
	var card_width := viewport_size.x * CARD_WIDTH_RATIO
	var card_height := card_width / CARD_ASPECT_RATIO
	var max_height := viewport_size.y * CARD_MAX_HEIGHT_RATIO

	if card_height > max_height:
		card_height = max_height
		card_width = card_height * CARD_ASPECT_RATIO

	return Vector2(card_width, card_height)

static func get_grid_size(viewport_size: Vector2) -> Vector2:
	var card_size := get_card_size(viewport_size)
	return Vector2(
		card_size.x * 2.0 + HORIZONTAL_GAP,
		card_size.y * 2.0 + VERTICAL_GAP
	)

static func get_rects(viewport_size: Vector2) -> Array[Rect2]:
	return get_result_rects(viewport_size, 4)

static func get_result_rects(viewport_size: Vector2, card_count: int) -> Array[Rect2]:
	var safe_count: int = clampi(card_count, 1, DriverRoster.DRIVER_IDS.size())
	var columns: int = 1
	if safe_count > 1:
		columns = 2
	if safe_count > 4:
		columns = 3
	var rows: int = ceili(float(safe_count) / float(columns))
	var horizontal_gap: float = HORIZONTAL_GAP
	var vertical_gap: float = 16.0 if rows >= 2 else VERTICAL_GAP
	var available_size := Vector2(
		maxf(0.0, viewport_size.x - 8.0),
		viewport_size.y * 0.82
	)
	var maximum_card_width: float = (
		available_size.x - horizontal_gap * float(columns - 1)
	) / float(columns)
	var maximum_card_height: float = (
		available_size.y - vertical_gap * float(rows - 1)
	) / float(rows)
	var authored_card_width: float = get_card_size(viewport_size).x
	var card_width: float = minf(
		minf(maximum_card_width, maximum_card_height * CARD_ASPECT_RATIO),
		authored_card_width
	)
	var card_height: float = card_width / CARD_ASPECT_RATIO
	card_width = maxf(0.0, card_width - 12.0)
	var card_size := Vector2(card_width, card_height)
	var grid_size := Vector2(
		card_size.x * float(columns) + horizontal_gap * float(columns - 1),
		card_size.y * float(rows) + vertical_gap * float(rows - 1)
	)
	var origin := (viewport_size - grid_size) * 0.5
	var rects: Array[Rect2] = []

	for index in safe_count:
		var column: int = index % columns
		var row: int = int(index / columns)
		var items_in_row: int = mini(columns, safe_count - row * columns)
		var row_width: float = (
			card_size.x * float(items_in_row)
			+ horizontal_gap * float(items_in_row - 1)
		)
		var row_origin_x: float = (viewport_size.x - row_width) * 0.5
		var position := Vector2(
			row_origin_x + float(column) * (card_size.x + horizontal_gap),
			origin.y + float(row) * (card_size.y + vertical_gap)
		)
		rects.append(Rect2(position, card_size))

	return rects
