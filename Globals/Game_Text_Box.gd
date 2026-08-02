extends CanvasLayer

signal text_finished

var dialogue_speed = 0.03
var dialogue_queue = []
var currently_typing = false
var skip_typing = false
var text_history = ""
var is_expanded = false

# Fade effect variables
var fade_timer = 0.0
var fade_duration = 3.0
var is_fading = false
var hover_timer = 0.0
var hover_duration = 2.0
var is_hovered = false

var text_timer: Timer
var next_text_delay: Timer
var tween: Tween
var rich_text_label: RichTextLabel

func _enter_tree():
	# Ensure this node is at the root and has a consistent name
	name = "Game_Text_Box"
	
func _ready():
	rich_text_label = RichTextLabel.new()
	add_child(rich_text_label)
	
	# Set up the RichTextLabel properties
	rich_text_label.name = "GameTextBox"
	rich_text_label.mouse_filter = Control.MOUSE_FILTER_STOP
	rich_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	rich_text_label.scroll_active = true
	rich_text_label.scroll_following = true
	rich_text_label.bbcode_enabled = true
	rich_text_label.fit_content = false
	
	# Set custom font
	var custom_font = load("res://Fonts/VeniceClassic.ttf")
	if custom_font:
		rich_text_label.add_theme_font_override("normal_font", custom_font)
	
	# Set custom font size
	rich_text_label.add_theme_font_size_override("normal_font_size", 24)
	
	# Set fixed size and center it at the bottom of the screen
	rich_text_label.size = Vector2(500, 175)
	update_textbox_position()
	
	# Connect signals
	rich_text_label.mouse_entered.connect(_on_mouse_enter)
	rich_text_label.mouse_exited.connect(_on_mouse_exit)
	
	# Initialize
	rich_text_label.text = ""
	rich_text_label.visible_characters = 0
	text_history = ""
	
	# Start visible but transparent, ready to fade in
	rich_text_label.modulate.a = 0.0
	rich_text_label.visible = true
	
	setup_timers()
	
	# Create tween for smooth fade effects
	tween = create_tween()
	tween.kill()

# Function to update text box position based on current viewport size
func update_textbox_position():
	var viewport_size = get_viewport().get_visible_rect().size
	rich_text_label.position = Vector2(
		(viewport_size.x - 500) / 2,  # Center horizontally
		viewport_size.y - 130  # Position near bottom with some margin
	)

func setup_timers():
	text_timer = Timer.new()
	text_timer.name = "TextTimer"
	add_child(text_timer)
	text_timer.timeout.connect(_on_text_timer_timeout)
	
	next_text_delay = Timer.new()
	next_text_delay.name = "NextTextDelay"
	next_text_delay.one_shot = true
	add_child(next_text_delay)
	next_text_delay.timeout.connect(_on_next_text_delay_timeout)

func display_text(new_text: String) -> void:
	# Make sure text box is visible when displaying text
	show_text_box()
	
	# Add text to queue
	dialogue_queue.append(new_text)
	
	# If not currently showing text, start showing it
	if not currently_typing:
		show_next_dialogue()

func show_next_dialogue():
	if dialogue_queue.size() == 0:
		return
	
	currently_typing = true
	var next_text = dialogue_queue.pop_front()
	
	# Only append new text if there's existing history
	if text_history != "":
		text_history += "\n"
	text_history += next_text
	rich_text_label.text = text_history
	
	# Reset visible characters before starting new animation
	rich_text_label.visible_characters = text_history.length() - next_text.length()
	text_timer.start(dialogue_speed)

func _on_text_timer_timeout():
	if rich_text_label.visible_characters < rich_text_label.text.length():
		rich_text_label.visible_characters += 1
		text_timer.start(dialogue_speed)
	else:
		text_timer.stop()
		currently_typing = false
		text_finished.emit()
		
		if dialogue_queue.size() > 0:
			next_text_delay.start(1.0)  # 1 second delay between messages
		else:
			# Start fade timer when all text is finished
			start_fade_timer()

func _process(delta):
	# Handle fade timer
	if rich_text_label.visible and not currently_typing and dialogue_queue.size() == 0 and not is_hovered:
		fade_timer += delta
		if fade_timer >= fade_duration and not is_fading:
			start_fade_out()
	
	# Handle hover timer
	if is_hovered and not rich_text_label.visible:
		hover_timer += delta
		if hover_timer >= hover_duration:
			show_text_box()

func start_fade_timer():
	# Reset fade timer when text is finished
	fade_timer = 0.0
	is_fading = false

func start_fade_out():
	is_fading = true
	tween.kill()
	tween = create_tween()
	tween.tween_property(rich_text_label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(_on_fade_out_complete)

func _on_fade_out_complete():
	rich_text_label.visible = false
	is_fading = false
	# Clear history when completely faded out
	clear_history()

func show_text_box():
	tween.kill()
	tween = create_tween()
	rich_text_label.visible = true
	tween.tween_property(rich_text_label, "modulate:a", 1.0, 0.3)
	fade_timer = 0.0
	is_fading = false

func _on_mouse_enter():
	is_hovered = true
	hover_timer = 0.0

func _on_mouse_exit():
	is_hovered = false
	hover_timer = 0.0

func _on_next_text_delay_timeout():
	show_next_dialogue()

func clear_history():
	rich_text_label.text = ""
	text_history = ""
	rich_text_label.visible_characters = 0
	dialogue_queue.clear()
	currently_typing = false

# Additional utility methods
func display_temporary_text(text: String, duration: float = 3.0) -> void:
	display_text(text)
	
	# Clear after duration
	var temp_timer = Timer.new()
	add_child(temp_timer)
	temp_timer.wait_time = duration
	temp_timer.one_shot = true
	temp_timer.timeout.connect(func(): 
		clear_history()
		temp_timer.queue_free()
	)
	temp_timer.start()

func is_typing() -> bool:
	return currently_typing

func skip_typing_animation():
	if currently_typing:
		rich_text_label.visible_characters = rich_text_label.text.length()
		text_timer.stop()
		currently_typing = false
		text_finished.emit()

# Configuration methods
func set_dialogue_speed(speed: float) -> void:
	dialogue_speed = speed

func set_textbox_position(new_position: Vector2) -> void:
	rich_text_label.position = new_position

func set_textbox_size(new_size: Vector2) -> void:
	rich_text_label.size = new_size
	# Update position to keep it centered after size change
	update_textbox_position()

# Handle window resizing
func _notification(what):
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		update_textbox_position()
