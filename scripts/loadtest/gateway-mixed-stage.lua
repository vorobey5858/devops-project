math.randomseed(os.time())

local request_counter = 0

local function random_item(index)
  local quantity = math.random(1, 3)
  local unit_price = math.random(10, 60) + math.random()
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
  local item_count = math.random(1, 3)
  local items = {}
  for index = 1, item_count do
    items[index] = random_item(index)
  end

  return string.format(
    "{\"customer_id\":\"cust-%d\",\"currency\":\"USD\",\"capture_payment\":true,\"items\":[%s]}",
    request_counter,
    table.concat(items, ",")
  )
end

request = function()
  local headers = {}
  headers["Host"] = "api-gateway.stage.platform.local"

  local dice = math.random(100)
  if dice <= 70 then
    headers["Content-Type"] = "application/json"
    return wrk.format("POST", "/api/checkout", headers, checkout_body())
  end

  if dice <= 88 then
    return wrk.format("GET", "/api/demo", headers)
  end

  return wrk.format("GET", "/api/downstream", headers)
end
