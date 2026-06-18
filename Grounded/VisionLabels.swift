import Foundation

struct VisionLabelCategory: Identifiable {
    let id: String
    let name: String
    let labels: [String]
}

/// Curated subsets of Apple Vision taxonomy identifiers (underscore format).
let visionLabelCategories: [VisionLabelCategory] = [
    VisionLabelCategory(id: "drink", name: "Drinks & Containers", labels: [
        "bottle", "cup", "mug", "wine_bottle", "beer", "thermos", "teapot", "kettle",
        "juice", "soda", "bowl"
    ]),
    VisionLabelCategory(id: "food", name: "Food", labels: [
        "apple", "banana", "oranges", "pizza", "sandwich", "salad",
        "bread", "cake", "cookie", "donut", "egg", "sushi", "rice", "taco", "burrito",
        "ice_cream", "chocolate"
    ]),
    VisionLabelCategory(id: "electronics", name: "Electronics", labels: [
        "laptop", "computer", "computer_keyboard", "computer_mouse", "computer_monitor",
        "phone", "television", "headphones", "calculator", "printer", "speakers_music"
    ]),
    VisionLabelCategory(id: "furniture", name: "Furniture & Home", labels: [
        "chair", "desk", "table", "bed", "sofa", "lamp", "bookshelf", "pillow",
        "curtain", "clock", "vase", "window"
    ]),
    VisionLabelCategory(id: "office", name: "Office & School", labels: [
        "book", "pen", "scissors", "envelope", "calendar", "whiteboard",
        "backpack", "briefcase"
    ]),
    VisionLabelCategory(id: "kitchen", name: "Kitchen", labels: [
        "refrigerator", "microwave", "toaster", "blender", "coffee",
        "plate", "bowl", "fork", "knife", "spoon", "cutting_board",
        "pan", "pot_cooking", "spatula", "oven"
    ]),
    VisionLabelCategory(id: "clothing", name: "Clothing & Accessories", labels: [
        "shoes", "sneaker", "boot", "hat", "sunglasses", "watch", "backpack",
        "purse", "wallet", "glove", "scarf", "jacket", "jeans"
    ]),
    VisionLabelCategory(id: "sports", name: "Sports & Exercise", labels: [
        "basketball", "football", "soccer", "tennis", "baseball", "bicycle",
        "dumbbell", "yoga", "golf_club", "swimming", "treadmill", "helmet", "skateboard"
    ]),
    VisionLabelCategory(id: "nature", name: "Nature & Outdoors", labels: [
        "tree", "flower", "plant", "grass", "rocks", "sun", "cloudy",
        "beach", "ocean", "river", "dog", "cat", "bird", "fish", "horse", "rabbit"
    ]),
    VisionLabelCategory(id: "tools", name: "Tools & Hardware", labels: [
        "hammer", "screwdriver", "wrench", "paintbrush", "bucket", "broom", "mop", "vacuum"
    ]),
    VisionLabelCategory(id: "bathroom", name: "Bathroom & Personal Care", labels: [
        "toothbrush", "soap", "towel", "shampoo", "razor", "comb", "hair_dryer", "tissue"
    ]),
]

/// Curated categories with excluded labels removed.
let filteredVisionLabelCategories: [VisionLabelCategory] = visionLabelCategories
    .map { category in
        VisionLabelCategory(
            id: category.id,
            name: category.name,
            labels: category.labels.filter { !VisionLabelCatalog.isExcluded($0) }
        )
    }
    .filter { !$0.labels.isEmpty }

let allVisionLabels: [String] = filteredVisionLabelCategories
    .flatMap(\.labels)
    .sorted()
