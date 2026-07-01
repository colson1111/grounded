import Foundation

struct VisionLabelCategory: Identifiable {
    let id: String
    let name: String
    let labels: [String]
}

/// CLIP zero-shot unlock categories, organized for the picker UI.
let clipLabelCategories: [VisionLabelCategory] = [
    VisionLabelCategory(id: "kitchen", name: "Kitchen Appliances", labels: [
        "refrigerator", "microwave", "dishwasher", "oven", "toaster", "toaster_oven",
        "blender", "coffee_maker", "espresso_machine", "stand_mixer", "air_fryer",
        "rice_cooker", "slow_cooker", "food_processor", "electric_kettle", "waffle_maker",
        "juicer", "bread_maker", "hot_plate", "range_hood", "wine_cooler"
    ]),
    VisionLabelCategory(id: "bathroom", name: "Bathroom", labels: [
        "toilet", "bathtub", "shower_head", "bathroom_scale", "towel_rack",
        "plunger", "medicine_cabinet"
    ]),
    VisionLabelCategory(id: "bedroom", name: "Bedroom", labels: [
        "bed", "dresser", "wardrobe", "nightstand", "alarm_clock", "ceiling_fan",
        "mattress", "bunk_bed", "crib", "changing_table"
    ]),
    VisionLabelCategory(id: "living_room", name: "Living Room", labels: [
        "sofa", "television", "bookshelf", "fireplace", "floor_lamp", "record_player",
        "dart_board", "grandfather_clock", "aquarium", "rug", "curtain", "mirror",
        "picture_frame", "candle", "candelabra"
    ]),
    VisionLabelCategory(id: "office", name: "Office", labels: [
        "desk", "filing_cabinet", "printer", "whiteboard", "desk_lamp", "office_chair",
        "wall_clock", "bulletin_board", "paper_shredder", "projector", "projector_screen",
        "server_rack", "router", "typewriter"
    ]),
    VisionLabelCategory(id: "furniture", name: "Furniture & Storage", labels: [
        "dining_table", "coat_rack", "shoe_rack", "umbrella_stand", "hat_rack",
        "wine_rack", "plant_pot", "shelf_unit", "ironing_board"
    ]),
    VisionLabelCategory(id: "garage_workshop", name: "Garage & Workshop", labels: [
        "workbench", "tool_chest", "toolbox", "power_drill", "circular_saw", "table_saw",
        "band_saw", "drill_press", "air_compressor", "shop_vac", "welding_mask",
        "jack_stand", "garage_door", "bench_vice", "ladder", "generator", "propane_tank"
    ]),
    VisionLabelCategory(id: "garden_outdoor", name: "Garden & Outdoor", labels: [
        "lawnmower", "wheelbarrow", "garden_trowel", "rake", "sprinkler", "garden_hose",
        "bird_feeder", "barbecue_grill", "patio_umbrella", "greenhouse", "compost_bin",
        "rain_barrel", "garden_gnome", "fire_pit", "picnic_table", "hammock", "flagpole",
        "fence", "gate", "pond", "wishing_well", "sundial", "statue", "storage_shed",
        "dog_house", "chicken_coop", "trampoline", "swing_set", "swimming_pool",
        "diving_board", "outdoor_shower", "snow_blower", "leaf_blower", "hedge_trimmer",
        "chainsaw", "pressure_washer"
    ]),
    VisionLabelCategory(id: "gym_sports", name: "Gym & Sports", labels: [
        "treadmill", "exercise_bike", "bench_press", "weight_rack", "barbell", "kettlebell",
        "punching_bag", "rowing_machine", "jump_rope", "medicine_ball", "foam_roller",
        "yoga_mat", "climbing_wall", "balance_beam", "elliptical_trainer", "stair_climber",
        "cable_machine", "pull_up_bar", "pommel_horse", "uneven_bars", "vaulting_horse",
        "resistance_band"
    ]),
    VisionLabelCategory(id: "school", name: "School", labels: [
        "globe", "microscope", "chalkboard", "whiteboard", "locker", "water_fountain",
        "fire_alarm_pull", "bulletin_board", "telescope", "balance_scale"
    ]),
    VisionLabelCategory(id: "vehicles", name: "Vehicles", labels: [
        "car", "motorcycle", "bicycle", "kayak", "canoe", "surfboard",
        "electric_scooter", "scooter", "skateboard", "tractor", "forklift"
    ]),
    VisionLabelCategory(id: "vehicles_accessories", name: "Vehicle Accessories", labels: [
        "steering_wheel", "spare_tire", "jumper_cables", "gas_pump", "jack_stand"
    ]),
    VisionLabelCategory(id: "instruments", name: "Musical Instruments", labels: [
        "piano", "guitar", "drum_kit", "violin", "trumpet", "xylophone",
        "cello", "tuba", "accordion", "record_player"
    ]),
    VisionLabelCategory(id: "medical_safety", name: "Medical & Safety", labels: [
        "first_aid_kit", "defibrillator", "crutches", "stethoscope",
        "blood_pressure_monitor", "wheelchair", "fire_extinguisher",
        "smoke_detector", "carbon_monoxide_detector"
    ]),
    VisionLabelCategory(id: "animals", name: "Pets & Animals", labels: [
        "birdcage", "aquarium", "dog_crate", "beehive", "dog_house",
        "chicken_coop", "horse_trough", "hay_bale"
    ]),
    VisionLabelCategory(id: "home_systems", name: "Home Systems & Utilities", labels: [
        "washing_machine", "dryer", "vacuum_cleaner", "sewing_machine", "ironing_board",
        "water_heater", "furnace", "breaker_box", "dehumidifier", "window_ac",
        "space_heater", "doorbell", "security_camera", "satellite_dish",
        "solar_panel", "wind_turbine", "utility_sink"
    ]),
    VisionLabelCategory(id: "games_leisure", name: "Games & Leisure", labels: [
        "pool_table", "ping_pong_table", "foosball_table", "pinball_machine",
        "arcade_cabinet", "hot_tub", "sauna", "dart_board", "basketball_hoop",
        "soccer_goal", "golf_bag", "fishing_rod", "snowboard", "ski",
        "backpack", "tent", "kayak", "canoe", "surfboard"
    ]),
    VisionLabelCategory(id: "miscellaneous", name: "Miscellaneous", labels: [
        "vending_machine", "atm", "phone_booth", "newspaper_stand", "post_box",
        "bus_stop", "trash_can", "recycling_bin", "dumpster", "fire_hydrant",
        "stop_sign", "parking_meter", "traffic_light", "street_lamp",
        "mailbox", "safe", "stroller", "fire_escape", "water_tower",
        "park_bench", "clock_radio", "suitcase", "pull_cart", "pallet",
        "cargo_shelf", "trophy", "wine_rack", "bookend", "cuckoo_clock",
        "picture_frame"
    ]),
]

// Keep old name for call sites in ProfileEditorView that reference filteredVisionLabelCategories
let filteredVisionLabelCategories: [VisionLabelCategory] = clipLabelCategories
let allVisionLabels: [String] = clipLabelCategories.flatMap(\.labels).sorted()
