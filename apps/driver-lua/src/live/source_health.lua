do
  local namespace = _G.AVM_PITWALL_F1
  local source_health = {}

  local function push_bounded(list, value, maximum)
    if value == nil then return end
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
  end

  local function lower(value)
    if value == "LIVE" then return "live" end
    if value == "PARTIAL" then return "partial" end
    if value == "STALE" then return "stale" end
    return "unavailable"
  end

  function source_health.new(config)
    config = config or {}
    return {
      state = "OFFLINE",
      previous_state = nil,
      stale_after_s = config.telemetry_stale_after_s or 2,
      transition_confirmations = config.source_transition_confirmations or 2,
      healthy_streak = 0,
      failure_streak = 0,
      last_usable_s = nil,
      last_current_s = nil,
      transitions = {},
      transition_limit = config.max_source_transitions or 16,
      last_reason = "INITIALIZATION",
    }
  end

  local function transition(state, next_state, reason, now_s)
    if state.state == next_state and state.last_reason == reason then return end
    state.previous_state = state.state
    state.state = next_state
    state.last_reason = reason
    push_bounded(state.transitions, {
      from = state.previous_state,
      to = next_state,
      reason = reason,
      at_s = now_s,
    }, state.transition_limit)
  end

  function source_health.update(state, now_s, input)
    input = input or {}
    local source_mode = input.source_mode or "live"
    local usable_core = input.usable_core == true
    local optional_degraded = input.optional_degraded == true
    local read_ok = input.read_ok ~= false
    state.last_current_s = now_s
    if source_mode == "mock" and usable_core then
      state.healthy_streak = state.healthy_streak + 1
      state.failure_streak = 0
      state.last_usable_s = now_s
      transition(state, "LIVE", "MOCK_SOURCE", now_s)
      return state.state
    end
    if usable_core and read_ok then
      state.healthy_streak = state.healthy_streak + 1
      state.failure_streak = 0
      state.last_usable_s = now_s
      local target = optional_degraded and "PARTIAL" or "LIVE"
      local reason = optional_degraded and "OPTIONAL_FIELDS_DEGRADED" or "CORE_FIELDS_RECOVERED"
      -- Recovery is immediate after a usable sample. Degradation requires
      -- repeated failures below, preventing one bad frame from flapping the UI.
      transition(state, target, reason, now_s)
      return state.state
    end
    state.healthy_streak = 0
    state.failure_streak = state.failure_streak + 1
    local age = state.last_usable_s ~= nil and math.max(0, now_s - state.last_usable_s) or nil
    if state.last_usable_s == nil then
      transition(state, "OFFLINE", input.reason or "NO_USABLE_CORE", now_s)
    elseif age ~= nil and age > state.stale_after_s then
      transition(state, "STALE", input.reason or "SOURCE_STALE", now_s)
    elseif state.failure_streak >= state.transition_confirmations then
      transition(state, "PARTIAL", input.reason or "CORE_READ_DEGRADED", now_s)
    end
    return state.state
  end

  function source_health.availability(state)
    return lower(state and state.state or "OFFLINE")
  end

  function source_health.diagnostics(state)
    if type(state) ~= "table" then return {} end
    local age = state.last_usable_s ~= nil and state.last_current_s ~= nil and math.max(0, state.last_current_s - state.last_usable_s) or nil
    return {
      state = state.state,
      previous_state = state.previous_state,
      availability = source_health.availability(state),
      last_reason = state.last_reason,
      last_usable_s = state.last_usable_s,
      current_age_s = age,
      healthy_streak = state.healthy_streak,
      failure_streak = state.failure_streak,
      transitions = state.transitions,
    }
  end

  namespace.live.source_health = source_health
end
