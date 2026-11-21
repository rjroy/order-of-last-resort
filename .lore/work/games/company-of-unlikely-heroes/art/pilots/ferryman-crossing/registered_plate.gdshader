shader_type canvas_item;
render_mode unshaded;

// Register the observed water edges of this exact plate onto the two D-column
// boundaries. The outer anchors are fixed so scenery doesn't drift across the
// whole frame. Only the plate is resampled; projection and hit testing never move.
const vec3 BANKS[12] = {
	vec3(0.0, 751.0, 958.0), vec3(176.0, 718.0, 932.0),
	vec3(320.0, 690.0, 902.0), vec3(433.0, 658.0, 879.0),
	vec3(480.0, 641.0, 857.0), vec3(530.0, 631.0, 836.0),
	vec3(570.0, 608.0, 840.0), vec3(640.0, 566.0, 831.0),
	vec3(720.0, 553.0, 813.0), vec3(800.0, 526.0, 787.0),
	vec3(900.0, 484.0, 754.0), vec3(1024.0, 450.0, 739.0)
};
uniform vec2 plate_size;
uniform vec2 bridge_contact;
uniform vec2 column_axis;
uniform vec2 row_axis;

void fragment() {
	vec2 p = UV * plate_size;
	vec2 painted_banks = BANKS[0].yz;
	for (int i = 1; i < BANKS.length(); i++) {
		if (p.y <= BANKS[i].x) {
			float weight = (p.y - BANKS[i - 1].x) / (BANKS[i].x - BANKS[i - 1].x);
			painted_banks = mix(BANKS[i - 1].yz, BANKS[i].yz, weight);
			break;
		}
	}
	float center = bridge_contact.x + (p.y - bridge_contact.y) * row_axis.x / row_axis.y;
	float half_water = 0.5 * (column_axis.x - column_axis.y * row_axis.x / row_axis.y);
	vec2 banks = vec2(center - half_water, center + half_water);
	const float LEFT = 170.0;
	const float RIGHT = 1330.0;
	float source_x = p.x;
	if (p.x > LEFT && p.x < banks.x) {
		source_x = mix(LEFT, painted_banks.x, (p.x - LEFT) / (banks.x - LEFT));
	} else if (p.x >= banks.x && p.x < banks.y) {
		source_x = mix(painted_banks.x, painted_banks.y, (p.x - banks.x) / (banks.y - banks.x));
	} else if (p.x >= banks.y && p.x < RIGHT) {
		source_x = mix(painted_banks.y, RIGHT, (p.x - banks.y) / (RIGHT - banks.y));
	}
	COLOR = texture(TEXTURE, vec2(source_x / plate_size.x, UV.y));
}
