extends RefCounted
## 상점(data/content/shops.json). 사는 값 = price_gp × price_mult, 파는 값 = price_gp × sell_rate(내림, 최소 1).
## 재고는 world["shop_stock"][상점][아이템]에 남는다(보급품 사재기 제한 — 9단계 악용 2).

const Interact := preload("res://scripts/rules/interact.gd")


static func stock(world: Dictionary, shop_id: String) -> Array:
	var shop := RulesDB.get_entry("shop", shop_id)
	if not world.has("shop_stock"):
		world["shop_stock"] = {}
	if not world["shop_stock"].has(shop_id):
		var s := {}
		for row: Dictionary in shop.get("stock", []):
			s[row["item"]] = int(row["count"])
		world["shop_stock"][shop_id] = s
	var out: Array = []
	for row: Dictionary in shop.get("stock", []):
		var item: String = row["item"]
		out.append({"item": item, "count": int(world["shop_stock"][shop_id].get(item, 0)), "price": buy_price(shop_id, item)})
	return out


static func buy_price(shop_id: String, item: String) -> int:
	var mult := 1.0
	for row: Dictionary in RulesDB.get_entry("shop", shop_id).get("stock", []):
		if row["item"] == item:
			mult = float(row.get("price_mult", 1.0))
	return maxi(1, ceili(float(RulesDB.get_entry("item", item).get("price_gp", 1)) * mult))


static func sell_price(shop_id: String, item: String) -> int:
	var rate := float(RulesDB.get_entry("shop", shop_id).get("sell_rate", 0.5))
	return maxi(1, floori(float(RulesDB.get_entry("item", item).get("price_gp", 1)) * rate))


static func buy(world: Dictionary, shop_id: String, item: String) -> Dictionary:
	stock(world, shop_id)
	var left := int(world["shop_stock"][shop_id].get(item, 0))
	if left <= 0:
		return {"ok": false, "reason": "재고가 없다"}
	var price := buy_price(shop_id, item)
	if not Interact.take(world, "gold", price):
		return {"ok": false, "reason": "골드가 모자란다"}
	world["shop_stock"][shop_id][item] = left - 1
	Interact.give(world, item)
	return {"ok": true, "price": price}


static func sell(world: Dictionary, shop_id: String, item: String) -> Dictionary:
	if RulesDB.get_entry("item", item).get("category", "") == "currency" or not Interact.take(world, item):
		return {"ok": false, "reason": "팔 물건이 없다"}
	var price := sell_price(shop_id, item)
	Interact.give(world, "gold", price)
	stock(world, shop_id)
	world["shop_stock"][shop_id][item] = int(world["shop_stock"][shop_id].get(item, 0)) + 1
	return {"ok": true, "price": price}
