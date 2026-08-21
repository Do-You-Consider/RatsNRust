class_name MenuTheme
extends RefCounted
## Tema del menú, construido por código.
##
## Antes cada botón repetía sus theme_override_* dentro del .tscn: ~40 líneas
## por panel, seis paneles. Con las pantallas nuevas eso era inmantenible y
## garantizaba que tarde o temprano dos botones dejaran de parecerse.
##
## Variaciones de tipo disponibles (Control.theme_type_variation):
##   "BigButton"   -> opción principal de cada pantalla
##   "GhostButton" -> volver / cancelar
##   "GoButton"    -> acción positiva (iniciar partida, listo)

const BG := Color(0.045, 0.04, 0.038, 0.95)
const BORDER := Color(0.32, 0.26, 0.18)
const BORDER_HOT := Color(0.85, 0.62, 0.25)
const TEXT := Color(0.88, 0.84, 0.76)
const TEXT_DIM := Color(0.56, 0.51, 0.44)
const TEXT_HOT := Color(1.0, 0.93, 0.80)
const ACCENT := Color(0.85, 0.45, 0.15)
const GOOD := Color(0.40, 0.90, 0.55)
const BAD := Color(1.0, 0.30, 0.22)


static func _sb(bg: Color, border: Color, bw: int = 1, pad_x: float = 10.0,
		pad_y: float = 4.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = bw
	s.border_width_top = bw
	s.border_width_right = bw
	s.border_width_bottom = bw
	s.border_color = border
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func create() -> Theme:
	var t := Theme.new()
	t.default_font_size = 8

	_button(t, "Button", 9, Color(0.10, 0.095, 0.088, 0.92))
	_button(t, "BigButton", 11, Color(0.12, 0.11, 0.10, 0.94))
	_button(t, "GhostButton", 8, Color(0.05, 0.048, 0.045, 0.75))
	_button(t, "GoButton", 10, Color(0.10, 0.26, 0.13, 0.95))
	t.set_type_variation("BigButton", "Button")
	t.set_type_variation("GhostButton", "Button")
	t.set_type_variation("GoButton", "Button")

	# El botón "listo/iniciar" se distingue por el borde verde, no por el
	# relleno: relleno verde plano se peleaba con los neones del fondo.
	t.set_stylebox("normal", "GoButton", _sb(Color(0.08, 0.20, 0.11, 0.95), GOOD))
	t.set_stylebox("hover", "GoButton", _sb(Color(0.30, 0.85, 0.42), Color(0.85, 1.0, 0.9)))
	t.set_color("font_color", "GoButton", Color(0.78, 1.0, 0.85))

	t.set_color("font_color", "GhostButton", TEXT_DIM)

	# --- Label ---
	t.set_font_size("font_size", "Label", 8)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	# --- PanelContainer ---
	t.set_stylebox("panel", "PanelContainer", _sb(BG, BORDER, 1, 8.0, 6.0))

	# --- LineEdit ---
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.03, 0.028, 0.025, 0.95), Color(0.45, 0.35, 0.22), 1, 6.0, 3.0))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0.05, 0.045, 0.035, 0.95), BORDER_HOT, 1, 6.0, 3.0))
	t.set_font_size("font_size", "LineEdit", 9)
	t.set_color("font_color", "LineEdit", Color(0.95, 0.85, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)

	# --- ItemList (lista de salas) ---
	t.set_stylebox("panel", "ItemList", _sb(Color(0.02, 0.019, 0.017, 0.92), Color(0.28, 0.23, 0.16), 1, 3.0, 3.0))
	t.set_stylebox("selected", "ItemList", _sb(Color(0.30, 0.16, 0.05, 0.95), BORDER_HOT, 1, 2.0, 1.0))
	t.set_stylebox("selected_focus", "ItemList", _sb(Color(0.38, 0.20, 0.06, 0.95), BORDER_HOT, 1, 2.0, 1.0))
	t.set_stylebox("hovered", "ItemList", _sb(Color(0.12, 0.10, 0.07, 0.7), Color(0, 0, 0, 0), 0, 2.0, 1.0))
	t.set_font_size("font_size", "ItemList", 7)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT_HOT)

	# --- CheckButton / HSlider usados en el modal de crear sala ---
	t.set_font_size("font_size", "CheckButton", 8)
	t.set_color("font_color", "CheckButton", TEXT)

	return t


static func _button(t: Theme, type_name: String, size: int, normal_bg: Color) -> void:
	t.set_stylebox("normal", type_name, _sb(normal_bg, BORDER))
	# Hover invertido (fondo crema, texto negro): es el mismo lenguaje de
	# terminal que ya tenía el menú viejo, y a 480x270 se lee de un vistazo.
	t.set_stylebox("hover", type_name, _sb(Color(0.90, 0.84, 0.74), Color(1, 0.95, 0.88)))
	t.set_stylebox("pressed", type_name, _sb(Color(0.65, 0.28, 0.08), Color(0.9, 0.45, 0.15)))
	t.set_stylebox("disabled", type_name, _sb(Color(0.06, 0.055, 0.05, 0.6), Color(0.18, 0.16, 0.13)))
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	t.set_font_size("font_size", type_name, size)
	t.set_color("font_color", type_name, TEXT)
	t.set_color("font_hover_color", type_name, Color(0.05, 0.04, 0.04))
	t.set_color("font_pressed_color", type_name, Color(1, 1, 1))
	t.set_color("font_disabled_color", type_name, Color(0.35, 0.32, 0.28))
