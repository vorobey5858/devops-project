math.randomseed(os.time())

local request_counter = 0

local function random_item(index)
  local quantity = math.random(1, 5)
  local unit_price = math.random(10, 90) + math.random()
  return string.format(
    "{\"sku\":\"SKU-%d-%d\",\"quantity\":%d,\"unit_price\":%.2f}",
    index,
    math.random(1000, 9999),
    quantity,
    unit_price
  )
end

local function checkout_body()
  request_counter = request_counter + 1
  local item_count = math.random(2, 5)
  local items = {}

  for index = 1, item_count do
    items[index] = random_item(index)
  end

  return string.format(
    "{\"customer_id\":\"prod-heavy-%d\",\"currency\":\"USD\",\"capture_payment\":true,\"items\":[%s]}",
    request_counter,
    table.concat(items, ",")
  )
end

request = function()
  local headers = {}
  headers["Content-Type"] = "application/json"
  return wrk.format("POST", "/api/checkout", headers, checkout_body())
end
