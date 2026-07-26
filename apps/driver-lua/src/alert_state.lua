local namespace = _G.AVM_PITWALL_F1
local alert_state = {}

local priority_rank = { low = 1, normal = 2, high = 3, critical = 4 }

local function rank(alert)
  return priority_rank[alert.priority] or 1
end

local function sound_for(alert)
  if rank(alert) >= 4 then
    return "critical"
  end
  if rank(alert) >= 3 then
    return "warning"
  end
  return "info"
end

local function key_for(alert)
  return alert.alert_id or table.concat({ alert.family or "message", alert.cause or alert.text or "unknown" }, ":")
end

local function is_active(alert)
  return alert.status == "active" or alert.status == "acknowledged"
end

local function sort_items(items)
  table.sort(items, function(left, right)
    if rank(left) == rank(right) then
      return (left.created_at or 0) < (right.created_at or 0)
    end
    return rank(left) > rank(right)
  end)
end

function alert_state.new()
  return { items = {}, last_update = 0 }
end

function alert_state.ingest(state, incoming, now)
  if type(state) ~= "table" or type(incoming) ~= "table" or type(incoming.text) ~= "string" then
    return false, "invalid"
  end
  local key = key_for(incoming)
  for index = 1, #state.items do
    local existing = state.items[index]
    if existing.key == key and is_active(existing) then
      existing.text = incoming.text
      existing.detail = incoming.detail
      existing.priority = incoming.priority or existing.priority
      existing.updated_at = now or existing.updated_at
      existing.requires_acknowledgement = incoming.requires_acknowledgement == true
      sort_items(state.items)
      return true, "deduplicated"
    end
  end
  if incoming.supersedes ~= nil then
    for index = 1, #state.items do
      if state.items[index].key == incoming.supersedes and is_active(state.items[index]) then
        state.items[index].status = "superseded"
        state.items[index].closed_at = now or 0
      end
    end
  end
  local item = {
    key = key,
    alert_id = incoming.alert_id or key,
    family = incoming.family or "engineer_message",
    text = incoming.text,
    detail = incoming.detail,
    priority = incoming.priority or "normal",
    requires_acknowledgement = incoming.requires_acknowledgement == true,
    status = "active",
    created_at = now or 0,
    updated_at = now or 0,
    last_delivered_at = now or 0,
    repeat_count = 0,
    max_repeats = namespace.config.max_alert_repeats,
    sound_kind = sound_for(incoming),
  }
  state.items[#state.items + 1] = item
  sort_items(state.items)
  return true, "created"
end

function alert_state.acknowledge(state, alert_id, now)
  if type(state) ~= "table" or type(alert_id) ~= "string" then
    return false, "invalid"
  end
  for index = 1, #state.items do
    local item = state.items[index]
    if item.alert_id == alert_id or item.key == alert_id then
      if item.status == "acknowledged" then
        return true, "already_acknowledged"
      end
      if not is_active(item) then
        return false, "not_active"
      end
      item.status = "acknowledged"
      item.acknowledged_at = now or item.updated_at
      return true, "acknowledged"
    end
  end
  return false, "not_found"
end

function alert_state.tick(state, now)
  if type(state) ~= "table" then
    return nil
  end
  local sound = nil
  for index = 1, #state.items do
    local item = state.items[index]
    if is_active(item) then
      local expiry = namespace.config.alert_expiry_seconds[item.priority] or 45
      if item.status == "active" and now - item.created_at >= expiry then
        item.status = "expired"
        item.closed_at = now
      elseif item.status == "active" and item.repeat_count < item.max_repeats then
        local cadence = namespace.config.alert_repeat_seconds[item.priority] or 30
        if now - item.last_delivered_at >= cadence then
          item.repeat_count = item.repeat_count + 1
          item.last_delivered_at = now
          sound = item.sound_kind
          break
        end
      end
    end
  end
  state.last_update = now
  return sound
end

function alert_state.active(state)
  if type(state) ~= "table" then
    return nil
  end
  sort_items(state.items)
  for index = 1, #state.items do
    if is_active(state.items[index]) then
      return state.items[index]
    end
  end
  return nil
end

function alert_state.counts(state)
  local result = { active = 0, acknowledged = 0, expired = 0, superseded = 0 }
  if type(state) ~= "table" then
    return result
  end
  for index = 1, #state.items do
    local status = state.items[index].status
    if result[status] ~= nil then
      result[status] = result[status] + 1
    end
  end
  return result
end

namespace.alert_state = alert_state
