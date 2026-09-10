#!/usr/bin/env python3
"""
Single source of truth for Grounded unlock-object categories.

Generates, from GROUPS below:
  - clip_eval/categories/categories_full.json   (id/display_name/prompts, for the eval harness)
  - Grounded/category_embeddings.json           (id -> 512-d MobileCLIP-S1 text embedding)
  - clip_eval/models/category_embeddings.json   (copy)
  - Grounded/VisionLabels.swift                 (grouped picker list, ids only)

Run:  clip_env/bin/python clip_eval/rebuild_categories.py
Add --no-embed to regenerate the JSON category list + Swift file without loading the model.
"""

import argparse
import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CLIP_EVAL = REPO / "clip_eval"

MODEL_NAME = "MobileCLIP-S1"
PRETRAINED = "datacompdr"

SECTION_TITLES = {
    "kitchen": "Kitchen Appliances",
    "bathroom": "Bathroom",
    "bedroom": "Bedroom",
    "living_room": "Living Room",
    "office": "Office",
    "furniture": "Furniture & Storage",
    "garage_workshop": "Garage & Workshop",
    "garden_outdoor": "Garden & Outdoor",
    "gym_sports": "Gym & Sports",
    "vehicles": "Vehicles",
    "vehicles_accessories": "Vehicle Accessories",
    "instruments": "Musical Instruments",
    "medical_safety": "Medical & Safety",
    "pets_animals": "Pets & Animals",
    "home_systems": "Home Systems & Utilities",
    "games_leisure": "Games & Leisure",
    "miscellaneous": "Miscellaneous",
}

HINTS = {
    "kitchen": "a kitchen appliance",
    "bathroom": "a bathroom fixture",
    "bedroom": "a piece of bedroom furniture",
    "living_room": "a piece of living room furniture",
    "office": "a piece of office furniture or equipment",
    "furniture": "a piece of home storage furniture",
    "garage_workshop": "a garage or workshop tool",
    "garden_outdoor": "an outdoor or garden object",
    "gym_sports": "a piece of exercise equipment",
    "vehicles": "a vehicle",
    "vehicles_accessories": "a car accessory",
    "instruments": "a musical instrument",
    "medical_safety": "a piece of medical or safety equipment",
    "pets_animals": "an item for pets or animals",
    "home_systems": "a home utility system",
    "games_leisure": "a game or leisure item",
    "miscellaneous": "a street or public object",
}

# id -> group. First occurrence wins; ids are globally unique.
GROUPS = {
    "kitchen": [
        # existing
        "refrigerator", "microwave", "dishwasher", "oven", "toaster", "toaster_oven",
        "blender", "coffee_maker", "espresso_machine", "stand_mixer", "air_fryer",
        "rice_cooker", "slow_cooker", "food_processor", "electric_kettle", "waffle_maker",
        "juicer", "bread_maker", "hot_plate", "range_hood", "wine_cooler",
        # new
        "chest_freezer", "upright_freezer", "mini_fridge", "kegerator", "trash_compactor",
        "garbage_disposal", "water_cooler", "kitchen_island", "pot_rack", "knife_block",
        "dish_rack", "spice_rack", "pantry_cabinet", "bar_cart", "microwave_cart",
        "bakers_rack", "kitchen_cart", "double_oven", "wall_oven", "cooktop",
        "gas_range", "electric_range", "deep_fryer", "popcorn_machine", "ice_maker",
        "dish_drying_rack", "stand_alone_pantry", "coffee_urn", "chafing_dish",
    ],
    "bathroom": [
        "toilet", "bathtub", "shower_head", "bathroom_scale", "towel_rack",
        "plunger", "medicine_cabinet",
        "bathroom_vanity", "linen_closet", "shower_stall", "bidet", "laundry_hamper",
        "towel_warmer", "vanity_mirror", "pedestal_sink", "corner_shower", "walk_in_tub",
        "jetted_tub", "shower_enclosure", "toilet_brush_holder",
    ],
    "bedroom": [
        "bed", "dresser", "wardrobe", "nightstand", "alarm_clock", "ceiling_fan",
        "mattress", "bunk_bed", "crib", "changing_table",
        "armoire", "chest_of_drawers", "vanity_table", "cedar_chest", "headboard",
        "trundle_bed", "murphy_bed", "cradle", "rocking_chair", "cheval_mirror",
        "blanket_chest", "box_spring", "canopy_bed", "four_poster_bed", "daybed",
        "platform_bed", "bed_frame", "valet_stand", "hope_chest", "toy_chest",
    ],
    "living_room": [
        "sofa", "television", "bookshelf", "fireplace", "floor_lamp", "record_player",
        "dart_board", "grandfather_clock", "aquarium", "rug", "curtain", "mirror",
        "picture_frame", "candle", "candelabra",
        "sectional_sofa", "loveseat", "recliner", "ottoman", "chaise_lounge",
        "coffee_table", "end_table", "console_table", "entertainment_center",
        "media_console", "tv_stand", "armchair", "wingback_chair", "bean_bag_chair",
        "futon", "credenza", "sideboard", "china_cabinet", "curio_cabinet", "hutch",
        "magazine_rack", "side_table", "accent_chair", "chesterfield_sofa",
        "display_cabinet", "drinks_cabinet", "gramophone", "table_lamp",
        "area_rug", "room_divider", "folding_screen",
    ],
    "office": [
        "desk", "filing_cabinet", "printer", "whiteboard", "desk_lamp", "office_chair",
        "wall_clock", "bulletin_board", "paper_shredder", "projector", "projector_screen",
        "server_rack", "router", "typewriter",
        "standing_desk", "drafting_table", "cubicle", "lateral_file_cabinet", "scanner",
        "plotter", "laminator", "water_dispenser", "monitor_arm", "executive_desk",
        "computer_desk", "conference_table", "reception_desk", "supply_cabinet",
        "storage_cabinet", "whiteboard_easel", "flip_chart", "printer_stand",
        "uninterruptible_power_supply", "task_chair", "globe", "microscope",
        "telescope", "balance_scale", "chalkboard", "bookcase",
    ],
    "furniture": [
        "dining_table", "coat_rack", "shoe_rack", "umbrella_stand", "hat_rack",
        "wine_rack", "plant_pot", "shelf_unit", "ironing_board",
        "closet_organizer", "cube_storage", "storage_ottoman", "storage_trunk",
        "footlocker", "storage_bench", "garment_rack", "wire_shelving", "utility_shelf",
        "blanket_ladder", "entryway_bench", "hall_tree", "shoe_cabinet", "cubby_unit",
        "locker", "steamer_trunk",
    ],
    "garage_workshop": [
        "workbench", "tool_chest", "toolbox", "power_drill", "circular_saw", "table_saw",
        "band_saw", "drill_press", "air_compressor", "shop_vac", "welding_mask",
        "jack_stand", "garage_door", "bench_vice", "ladder", "generator", "propane_tank",
        "miter_saw", "scroll_saw", "jointer", "thickness_planer", "wood_lathe",
        "metal_lathe", "angle_grinder", "bench_grinder", "belt_sander", "orbital_sander",
        "router_table", "sawhorse", "pegboard", "tool_cabinet", "rolling_tool_cart",
        "mechanics_creeper", "engine_hoist", "engine_stand", "floor_jack", "air_tank",
        "parts_washer", "machinist_vise", "anvil", "shop_press", "utility_cart",
        "work_light", "extension_cord_reel", "welding_table", "welder", "plasma_cutter",
        "cement_mixer", "wet_saw", "radial_arm_saw", "dust_collector", "lumber_rack",
        "step_ladder", "extension_ladder", "scaffold",
    ],
    "garden_outdoor": [
        "lawnmower", "wheelbarrow", "garden_trowel", "rake", "sprinkler", "garden_hose",
        "bird_feeder", "barbecue_grill", "patio_umbrella", "greenhouse", "compost_bin",
        "rain_barrel", "garden_gnome", "fire_pit", "picnic_table", "hammock", "flagpole",
        "fence", "gate", "pond", "wishing_well", "sundial", "statue", "storage_shed",
        "dog_house", "chicken_coop", "trampoline", "swing_set", "swimming_pool",
        "diving_board", "outdoor_shower", "snowblower", "leaf_blower", "hedge_trimmer",
        "chainsaw", "pressure_washer",
        "garden_shed", "gazebo", "pergola", "arbor", "trellis", "raised_garden_bed",
        "planter_box", "cold_frame", "hose_reel", "garden_cart", "potting_bench",
        "firewood_rack", "chiminea", "outdoor_fireplace", "garden_fountain", "bird_bath",
        "lawn_ornament", "mailbox_post", "lamppost", "bollard", "retaining_wall",
        "deck", "porch_swing", "glider_bench", "adirondack_chair", "patio_set",
        "outdoor_sofa", "hammock_stand", "clothesline", "clothes_drying_rack",
        "garden_bench", "kids_playhouse", "playground_slide", "seesaw", "monkey_bars",
        "sandbox", "kiddie_pool", "above_ground_pool", "pool_ladder", "pool_pump",
        "pool_filter", "pool_heater", "boat_lift", "dock", "awning", "carport",
        "cornhole_set", "horseshoe_pit", "batting_cage", "fire_ring", "camp_stove",
        "camping_cooler", "ice_chest", "wood_chipper", "tiller", "edger",
        "post_hole_digger",
    ],
    "gym_sports": [
        "treadmill", "exercise_bike", "bench_press", "weight_rack", "barbell", "kettlebell",
        "punching_bag", "rowing_machine", "jump_rope", "medicine_ball", "foam_roller",
        "yoga_mat", "climbing_wall", "balance_beam", "elliptical_trainer", "stair_climber",
        "cable_machine", "pull_up_bar", "pommel_horse", "uneven_bars", "vaulting_horse",
        "resistance_band",
        "squat_rack", "power_rack", "smith_machine", "leg_press", "lat_pulldown_machine",
        "dip_station", "roman_chair", "hyperextension_bench", "preacher_curl_bench",
        "adjustable_bench", "flat_bench", "dumbbell_rack", "weight_plate_tree",
        "battle_ropes", "weight_sled", "prowler_sled", "plyo_box", "gymnastics_rings",
        "parallettes", "ab_wheel", "spin_bike", "air_bike", "ski_erg", "aerobic_stepper",
        "leg_curl_machine", "leg_extension_machine", "chest_press_machine",
        "shoulder_press_machine", "seated_row_machine", "pec_deck", "hack_squat_machine",
        "calf_raise_machine", "glute_ham_developer", "functional_trainer", "half_rack",
        "heavy_bag_stand", "speed_bag_platform", "boxing_ring", "wrestling_mat",
        "cable_crossover", "incline_bench", "decline_bench", "ez_curl_bar",
        "sit_up_bench", "captains_chair", "vibration_plate", "bike_trainer",
    ],
    "vehicles": [
        "car", "motorcycle", "bicycle", "kayak", "canoe", "surfboard",
        "electric_scooter", "scooter", "skateboard", "tractor", "forklift",
        "pickup_truck", "cargo_van", "passenger_van", "minivan", "suv", "sedan",
        "hatchback", "station_wagon", "convertible", "box_truck", "dump_truck",
        "garbage_truck", "travel_trailer", "camper_van", "motorhome", "rv",
        "fifth_wheel_trailer", "utility_trailer", "boat_trailer", "flatbed_trailer",
        "rowboat", "sailboat", "motorboat", "pontoon_boat", "jet_ski", "dinghy",
        "dirt_bike", "moped", "golf_cart", "atv", "side_by_side", "snowmobile",
        "riding_mower", "zero_turn_mower", "go_kart", "dune_buggy", "segway",
        "hoverboard", "unicycle", "tandem_bicycle", "cargo_bike", "recumbent_bike",
        "tricycle", "hand_truck", "furniture_dolly", "pallet_jack",
    ],
    "vehicles_accessories": [
        "steering_wheel", "spare_tire", "jumper_cables", "gas_pump",
        "car_battery", "car_jack", "lug_wrench", "floor_mats", "car_cover", "roof_rack",
        "roof_cargo_box", "tow_hitch", "jump_starter", "tire_inflator", "gas_can",
        "oil_drain_pan", "car_ramps", "wheel_chocks", "tire_rack", "hitch_bike_rack",
        "snow_chains", "car_seat", "booster_seat", "cargo_carrier", "winch",
        "recovery_straps", "engine_block",
    ],
    "instruments": [
        "piano", "guitar", "drum_kit", "violin", "trumpet", "xylophone",
        "cello", "tuba", "accordion",
        "electric_keyboard", "synthesizer", "pipe_organ", "electronic_organ", "harp",
        "banjo", "mandolin", "ukulele", "double_bass", "saxophone", "clarinet",
        "flute", "oboe", "bassoon", "french_horn", "trombone", "harmonica", "bagpipes",
        "marimba", "vibraphone", "timpani", "conga_drums", "bongo_drums", "djembe",
        "cajon", "guitar_amplifier", "pa_speaker", "mixing_console", "keyboard_stand",
        "music_stand", "grand_piano", "upright_piano", "electric_guitar", "bass_guitar",
        "harpsichord", "piano_bench",
    ],
    "medical_safety": [
        "first_aid_kit", "defibrillator", "crutches", "stethoscope",
        "blood_pressure_monitor", "wheelchair", "fire_extinguisher", "smoke_detector",
        "carbon_monoxide_detector",
        "hospital_bed", "walker", "rollator", "walking_cane", "mobility_scooter",
        "oxygen_concentrator", "nebulizer", "cpap_machine", "patient_lift", "exam_table",
        "iv_pole", "aed_cabinet", "eyewash_station", "safety_shower", "fire_blanket",
        "sharps_container", "wheelchair_ramp", "stair_lift", "shower_chair",
        "transfer_bench", "bed_rail", "commode_chair", "oxygen_tank",
        "fire_alarm_pull", "first_aid_station",
    ],
    "pets_animals": [
        "birdcage", "dog_crate", "beehive", "horse_trough", "hay_bale",
        "fish_tank", "terrarium", "vivarium", "hamster_cage", "rabbit_hutch",
        "litter_box", "cat_tree", "scratching_post", "dog_kennel", "dog_bed",
        "pet_crate", "aviary", "horse_stall", "feed_trough", "hay_rack", "saddle_rack",
        "tack_trunk", "chicken_run", "duck_house", "pig_pen", "goat_shelter",
        "water_trough", "dog_run", "pet_gate", "pet_playpen", "reptile_enclosure",
        "aquarium_stand",
    ],
    "home_systems": [
        "washing_machine", "dryer", "vacuum_cleaner", "sewing_machine", "water_heater",
        "furnace", "breaker_box", "dehumidifier", "window_ac", "space_heater",
        "doorbell", "security_camera", "satellite_dish", "solar_panel", "wind_turbine",
        "utility_sink",
        "water_softener", "sump_pump", "well_pump", "boiler", "heat_pump", "ac_condenser",
        "air_handler", "water_storage_tank", "pressure_tank", "electrical_subpanel",
        "transfer_switch", "standby_generator", "ev_charger", "smart_thermostat",
        "gas_meter", "water_meter", "radiator", "baseboard_heater", "wood_stove",
        "pellet_stove", "chimney", "water_filtration_system", "tankless_water_heater",
        "septic_tank", "oil_tank", "ductless_mini_split", "whole_house_fan", "attic_fan",
        "water_pump", "air_purifier", "electrical_meter", "fuse_box", "water_fountain",
    ],
    "games_leisure": [
        "pool_table", "ping_pong_table", "foosball_table", "pinball_machine",
        "arcade_cabinet", "hot_tub", "sauna", "basketball_hoop", "soccer_goal",
        "golf_bag", "fishing_rod", "snowboard", "ski", "backpack", "tent",
        "air_hockey_table", "shuffleboard_table", "poker_table", "dartboard_cabinet",
        "jukebox", "claw_machine", "snooker_table", "bumper_pool_table",
        "karaoke_machine", "home_theater_system", "popcorn_cart", "humidor_cabinet",
        "billiard_table", "cornhole_boards", "table_shuffleboard", "mahjong_table",
        "mini_bar", "dance_pole", "ball_pit", "climbing_dome", "spring_rocker",
        "golf_simulator", "putting_green",
    ],
    "miscellaneous": [
        "vending_machine", "atm", "phone_booth", "newspaper_stand", "post_box",
        "bus_stop", "trash_can", "recycling_bin", "dumpster", "fire_hydrant",
        "stop_sign", "parking_meter", "traffic_light", "street_lamp", "mailbox",
        "safe", "stroller", "fire_escape", "water_tower", "park_bench", "clock_radio",
        "suitcase", "pull_cart", "pallet", "cargo_shelf", "trophy", "bookend",
        "cuckoo_clock",
        "picnic_shelter", "transit_shelter", "information_kiosk", "ticket_machine",
        "pay_station", "bike_share_dock", "ev_charging_station", "standpipe",
        "utility_box", "transformer_box", "junction_box", "traffic_cone",
        "road_barricade", "jersey_barrier", "guardrail", "billboard", "bike_locker",
        "luggage_cart", "shopping_cart", "wheeled_bin", "tree_grate",
        "bike_repair_station", "parking_gate", "toll_booth", "guard_shack",
        "portable_toilet", "shipping_container", "telephone_pole", "transmission_tower",
        "cell_tower", "grain_silo", "windmill",
    ],
}


# ~200-category subset used for the eval harness (the other ~570 ship in the app
# untested). Mix of common household/office/garage/car items plus the categories
# that scored worst in the old results_log.
CORE_IDS = set("""
refrigerator microwave dishwasher oven toaster toaster_oven blender coffee_maker
espresso_machine stand_mixer air_fryer rice_cooker slow_cooker food_processor
electric_kettle range_hood mini_fridge chest_freezer kegerator ice_maker
bar_cart kitchen_island
toilet bathtub shower_head bathroom_scale towel_rack medicine_cabinet
bathroom_vanity linen_closet laundry_hamper pedestal_sink
bed dresser wardrobe nightstand alarm_clock ceiling_fan mattress bunk_bed crib
armoire chest_of_drawers headboard rocking_chair daybed
sofa television bookshelf fireplace floor_lamp record_player dart_board
grandfather_clock aquarium rug mirror picture_frame sectional_sofa loveseat
recliner ottoman coffee_table end_table entertainment_center tv_stand armchair
futon credenza sideboard china_cabinet bookcase
desk filing_cabinet printer whiteboard desk_lamp office_chair wall_clock
projector standing_desk conference_table scanner globe microscope telescope
dining_table coat_rack shoe_rack wine_rack plant_pot shelf_unit ironing_board
storage_bench garment_rack locker
workbench tool_chest toolbox power_drill circular_saw table_saw drill_press
air_compressor shop_vac ladder generator propane_tank miter_saw bench_grinder
belt_sander sawhorse pegboard rolling_tool_cart floor_jack engine_hoist
welder cement_mixer step_ladder
lawnmower wheelbarrow rake garden_hose barbecue_grill patio_umbrella greenhouse
compost_bin fire_pit picnic_table hammock fence gate storage_shed dog_house
trampoline swing_set diving_board leaf_blower hedge_trimmer chainsaw
pressure_washer gazebo pergola trellis raised_garden_bed potting_bench
adirondack_chair porch_swing garden_bench sandbox kiddie_pool patio_set
treadmill exercise_bike bench_press weight_rack barbell kettlebell punching_bag
rowing_machine yoga_mat elliptical_trainer stair_climber squat_rack power_rack
smith_machine leg_press lat_pulldown_machine adjustable_bench dumbbell_rack
spin_bike battle_ropes
car motorcycle bicycle kayak canoe surfboard electric_scooter skateboard tractor
forklift pickup_truck minivan suv sedan cargo_van rv travel_trailer utility_trailer
sailboat jet_ski atv golf_cart snowmobile riding_mower go_kart
steering_wheel spare_tire jumper_cables gas_pump car_battery car_jack roof_rack
tow_hitch tire_inflator gas_can car_ramps
piano guitar drum_kit violin trumpet cello accordion electric_keyboard
synthesizer harp banjo saxophone clarinet flute trombone marimba
guitar_amplifier grand_piano upright_piano electric_guitar
first_aid_kit defibrillator crutches wheelchair fire_extinguisher smoke_detector
hospital_bed walker mobility_scooter oxygen_concentrator exam_table iv_pole
birdcage dog_crate beehive fish_tank terrarium hamster_cage rabbit_hutch
litter_box cat_tree dog_kennel dog_bed aviary horse_stall feed_trough
washing_machine dryer vacuum_cleaner sewing_machine water_heater furnace
breaker_box dehumidifier space_heater security_camera satellite_dish solar_panel
wind_turbine sump_pump boiler heat_pump radiator wood_stove pellet_stove
water_softener ev_charger
pool_table ping_pong_table foosball_table pinball_machine arcade_cabinet hot_tub
sauna basketball_hoop soccer_goal golf_bag fishing_rod snowboard ski tent
air_hockey_table jukebox karaoke_machine
vending_machine atm phone_booth trash_can recycling_bin dumpster fire_hydrant
stop_sign parking_meter traffic_light street_lamp mailbox safe stroller
water_tower park_bench suitcase shopping_cart portable_toilet shipping_container
telephone_pole grain_silo windmill
""".split())


def display_name(cid: str) -> str:
    return cid.replace("_", " ").title()


def _a(n: str) -> str:
    return "an" if n[:1] in "aeiou" else "a"


def prompts_for(cid: str, group: str) -> list[str]:
    n = cid.replace("_", " ")
    art = _a(n)
    return [f"a photo of {art} {n}", f"{art} {n}", f"{art} {n}, {HINTS[group]}"]


def build_category_list() -> list[dict]:
    seen: set[str] = set()
    out: list[dict] = []
    for group, ids in GROUPS.items():
        for cid in ids:
            if cid in seen:
                raise ValueError(f"duplicate id {cid!r} (in {group})")
            seen.add(cid)
            out.append({
                "id": cid,
                "display_name": display_name(cid),
                "group": group,
                "prompts": prompts_for(cid, group),
            })
    return out


def check_existing_coverage(ids: set[str]) -> None:
    emb = REPO / "Grounded" / "category_embeddings.json"
    if not emb.exists():
        return
    old = set(json.loads(emb.read_text()).keys())
    # allow the known rename snow_blower -> snowblower
    dropped = old - ids - {"snow_blower"}
    if dropped:
        print(f"WARNING: {len(dropped)} previously-shipped ids dropped: {sorted(dropped)}")
    else:
        print(f"OK: all {len(old)} previously-shipped ids retained")


def write_swift(cats: list[dict]) -> None:
    by_group: dict[str, list[str]] = {}
    for c in cats:
        by_group.setdefault(c["group"], []).append(c["id"])

    lines = [
        "import Foundation",
        "",
        "struct VisionLabelCategory: Identifiable {",
        "    let id: String",
        "    let name: String",
        "    let labels: [String]",
        "}",
        "",
        "// GENERATED by clip_eval/rebuild_categories.py — do not edit by hand.",
        "// CLIP zero-shot unlock categories, organized for the picker UI.",
        "let clipLabelCategories: [VisionLabelCategory] = [",
    ]
    for group in GROUPS:
        ids = by_group.get(group, [])
        title = SECTION_TITLES[group].replace('"', '\\"')
        lines.append(f'    VisionLabelCategory(id: "{group}", name: "{title}", labels: [')
        row: list[str] = []
        for cid in ids:
            row.append(f'"{cid}"')
            if len(row) == 6:
                lines.append("        " + ", ".join(row) + ",")
                row = []
        if row:
            lines.append("        " + ", ".join(row) + ",")
        lines.append("    ]),")
    lines += [
        "]",
        "",
        "// Keep old name for call sites in ProfileEditorView that reference filteredVisionLabelCategories",
        "let filteredVisionLabelCategories: [VisionLabelCategory] = clipLabelCategories",
        "let allVisionLabels: [String] = clipLabelCategories.flatMap(\\.labels).sorted()",
        "",
    ]
    (REPO / "Grounded" / "VisionLabels.swift").write_text("\n".join(lines))
    print(f"wrote Grounded/VisionLabels.swift  ({len(cats)} labels, {len(GROUPS)} sections)")


def embed(cats: list[dict]) -> None:
    import open_clip
    import torch

    print(f"loading {MODEL_NAME} / {PRETRAINED} ...")
    model, _, _ = open_clip.create_model_and_transforms(MODEL_NAME, pretrained=PRETRAINED)
    model.eval()
    tokenizer = open_clip.get_tokenizer(MODEL_NAME)

    out: dict[str, list[float]] = {}
    B = 256
    for i in range(0, len(cats), B):
        chunk = cats[i:i + B]
        flat: list[str] = []
        spans: list[tuple[int, int]] = []
        for c in chunk:
            spans.append((len(flat), len(flat) + len(c["prompts"])))
            flat.extend(c["prompts"])
        with torch.no_grad():
            feats = model.encode_text(tokenizer(flat))
            feats = feats / feats.norm(dim=-1, keepdim=True)
        for c, (a, b) in zip(chunk, spans):
            v = feats[a:b].mean(dim=0)
            v = v / v.norm()
            out[c["id"]] = v.tolist()
        print(f"  embedded {min(i + B, len(cats))}/{len(cats)}")

    dim = len(next(iter(out.values())))
    dst_app = REPO / "Grounded" / "category_embeddings.json"
    dst_eval = CLIP_EVAL / "models" / "category_embeddings.json"
    payload = json.dumps(out, separators=(",", ":"))
    dst_app.write_text(payload)
    shutil.copyfile(dst_app, dst_eval)
    print(f"wrote {dst_app.relative_to(REPO)}  ({len(out)} categories, dim {dim})")
    print(f"wrote {dst_eval.relative_to(REPO)}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-embed", action="store_true", help="skip model load / embeddings")
    args = ap.parse_args()

    cats = build_category_list()
    ids = {c["id"] for c in cats}
    print(f"{len(cats)} categories across {len(GROUPS)} groups")
    check_existing_coverage(ids)

    def dump(path: Path, rows: list[dict]) -> None:
        path.write_text(json.dumps(
            [{k: c[k] for k in ("id", "display_name", "prompts")} for c in rows],
            indent=1,
        ))
        print(f"wrote {path.relative_to(REPO)}  ({len(rows)} categories)")

    dump(CLIP_EVAL / "categories" / "categories_full.json", cats)

    unknown = CORE_IDS - ids
    if unknown:
        raise ValueError(f"CORE_IDS not in catalog: {sorted(unknown)}")
    core = [c for c in cats if c["id"] in CORE_IDS]
    dump(CLIP_EVAL / "categories" / "categories_core.json", core)

    write_swift(cats)

    if not args.no_embed:
        embed(cats)


if __name__ == "__main__":
    main()
