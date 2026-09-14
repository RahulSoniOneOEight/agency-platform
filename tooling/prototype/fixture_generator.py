from __future__ import annotations

import random

SUPPORTED_INDUSTRIES = {
    "electronics-appliances",
    "furniture-home",
    "grocery-fmcg",
    "services-booking",
}

_NAMES = {
    "electronics-appliances": [
        "USB-C Hub", "Wireless Mouse", "Mechanical Keyboard", "27-inch Monitor",
        "Laptop Stand", "65W Charger", "Noise-Cancel Headphones", "Portable SSD",
    ],
    "furniture-home": [
        "Oak Side Table", "Lounge Chair", "Modular Sofa", "Dining Bench",
        "Floor Lamp", "Storage Console", "Coffee Table", "Bedside Cabinet",
    ],
    "grocery-fmcg": [
        "Basmati Rice", "Cold Pressed Oil", "Roasted Almonds", "Green Tea",
        "Pasta", "Tomato Puree", "Breakfast Oats", "Dark Chocolate",
    ],
}

_SERVICES = [
    "Initial Consultation", "Express Repair", "Home Visit", "Annual Maintenance",
    "Installation", "Inspection", "Premium Support", "Follow-up Session",
]


def generate_fixture_pack(industry: str, seed: int = 108) -> dict:
    if industry not in SUPPORTED_INDUSTRIES:
        raise ValueError(f"unsupported fixture industry: {industry}")
    rng = random.Random(seed)
    if industry == "services-booking":
        services = [
            {
                "id": f"svc-{i+1:02d}",
                "name": name,
                "price": 499 + (i * 250),
                "duration_minutes": 30 + (i % 4) * 15,
                "rating": round(4.1 + rng.random() * 0.8, 1),
            }
            for i, name in enumerate(_SERVICES)
        ]
        return {"industry": industry, "seed": seed, "products": [], "services": services}

    names = _NAMES[industry]
    products = []
    for i, name in enumerate(names):
        base = 299 + (i + 1) * 375
        products.append(
            {
                "id": f"prd-{i+1:02d}",
                "sku": f"SKU-{industry[:3].upper()}-{1000+i}",
                "name": name,
                "price": base,
                "compare_at": base + (0 if i % 3 == 0 else 250),
                "rating": round(4.0 + rng.random() * 0.9, 1),
                "stock": 8 + rng.randint(0, 72),
                "category": f"category-{(i % 4) + 1}",
            }
        )
    return {"industry": industry, "seed": seed, "products": products, "services": []}
