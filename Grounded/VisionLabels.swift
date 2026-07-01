import Foundation

struct VisionLabelCategory: Identifiable {
    let id: String
    let name: String
    let labels: [String]
}

/// CLIP zero-shot unlock categories, organized for the picker UI.
let clipLabelCategories: [VisionLabelCategory] = [
    VisionLabelCategory(id: "kitchen", name: "Kitchen Appliances", labels: [
        "refrigerator", "microwave", "dishwasher", "washing_machine", "ironing_board"
    ]),
    VisionLabelCategory(id: "bathroom", name: "Bathroom", labels: [
        "toilet", "bathtub"
    ]),
    VisionLabelCategory(id: "furniture", name: "Furniture", labels: [
        "sofa", "bed", "dining_table", "bookshelf", "desk", "filing_cabinet", "coat_rack",
        "grandfather_clock"
    ]),
    VisionLabelCategory(id: "electronics", name: "Electronics", labels: [
        "television", "printer"
    ]),
    VisionLabelCategory(id: "exercise", name: "Exercise Equipment", labels: [
        "treadmill", "exercise_bike", "bench_press", "weight_rack"
    ]),
    VisionLabelCategory(id: "instruments", name: "Musical Instruments", labels: [
        "piano", "guitar", "drum_kit"
    ]),
    VisionLabelCategory(id: "vehicles", name: "Vehicles", labels: [
        "car", "motorcycle", "bicycle", "kayak"
    ]),
    VisionLabelCategory(id: "outdoor", name: "Outdoor & Street", labels: [
        "fire_hydrant", "stop_sign", "parking_meter", "traffic_light", "park_bench",
        "mailbox", "trash_can", "garden_hose", "lawnmower", "barbecue_grill"
    ]),
    VisionLabelCategory(id: "tools", name: "Tools & Storage", labels: [
        "ladder", "power_drill", "toolbox", "fire_extinguisher", "safe"
    ]),
    VisionLabelCategory(id: "misc", name: "Other", labels: [
        "surfboard", "wheelchair", "stroller", "tent", "whiteboard",
        "vending_machine", "aquarium"
    ]),
]

// Keep old name for call sites in ProfileEditorView that reference filteredVisionLabelCategories
let filteredVisionLabelCategories: [VisionLabelCategory] = clipLabelCategories
let allVisionLabels: [String] = clipLabelCategories.flatMap(\.labels).sorted()
