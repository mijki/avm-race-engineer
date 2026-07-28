do
  local namespace = _G.AVM_PITWALL_F1
  local contracts = namespace.contracts
  local pit_learning = {}

  pit_learning.states = {
    ON_TRACK = "ON_TRACK",
    ENTRY_CANDIDATE = "ENTRY_CANDIDATE",
    IN_PIT_LANE = "IN_PIT_LANE",
    AT_PIT_BOX = "AT_PIT_BOX",
    LEAVING_PIT_BOX = "LEAVING_PIT_BOX",
    EXIT_CANDIDATE = "EXIT_CANDIDATE",
    BACK_ON_TRACK = "BACK_ON_TRACK",
    RESET_SUPPRESSED = "RESET_SUPPRESSED",
  }

  pit_learning.classifications = {
    DRIVE_THROUGH = "DRIVE_THROUGH",
    STOP_GO = "STOP_GO",
    SERVICE_STOP = "SERVICE_STOP",
    UNKNOWN_STOP = "UNKNOWN_STOP",
  }

  local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
  end

  local function copy(value)
    return contracts.copy(value)
  end

  local function bounded(list, value, maximum)
    if value == nil then return end
    list[#list + 1] = value
    while #list > maximum do table.remove(list, 1) end
  end

  local function identity_key(snapshot)
    return contracts.identity_key(snapshot and snapshot.identity or {})
  end

  local function car(snapshot)
    return snapshot and snapshot.car or {}
  end

  local function pit_lane(snapshot)
    local current_car = car(snapshot)
    return current_car.pit_lane == true or current_car.isInPitlane == true
  end

  local function pit_box(snapshot)
    local current_car = car(snapshot)
    return current_car.pit_box == true or current_car.isInPit == true
  end

  local function confirmed(value)
    if value == true then return true end
    if type(value) == "string" then
      local token = string.upper(value)
      return token == "CONFIRMED" or token == "COMPLETE" or token == "COMPLETED" or token == "DONE" or token == "APPLIED" or token == "VERIFIED" or token == "TRUE"
    end
    if type(value) == "table" then
      for _, key in ipairs({ "confirmed", "complete", "completed", "done", "applied", "verified" }) do
        if confirmed(value[key]) then return true end
      end
    end
    return false
  end

  local function service_signal(snapshot, names)
    local sections = { snapshot, snapshot and snapshot.service, snapshot and snapshot.pit_service, snapshot and snapshot.planned_service, snapshot and snapshot.strategy, snapshot and snapshot.session, snapshot and snapshot.car, snapshot and snapshot.tyres }
    for section_index = 1, #sections do
      local section = sections[section_index]
      if type(section) == "table" then
        for name_index = 1, #names do
          local name = names[name_index]
          if confirmed(section[name]) then return name end
        end
      end
    end
    return nil
  end

  local function service_evidence(previous, snapshot, fuel_jump_l)
    local evidence = {}
    local current_car, previous_car = car(snapshot), car(previous)
    if number(current_car.fuel_l) and number(previous_car.fuel_l) and current_car.fuel_l - previous_car.fuel_l >= (fuel_jump_l or 1) then
      evidence[#evidence + 1] = { kind = "FUEL_INCREASE", delta_l = current_car.fuel_l - previous_car.fuel_l }
    end
    if service_signal(snapshot, { "tyre_replacement_confirmed", "tyres_replaced", "tyre_change_confirmed", "tyre_reset_verified", "tyres_reset", "tyre_reset" }) ~= nil then
      evidence[#evidence + 1] = { kind = "TYRE_REPLACEMENT" }
    end
    local previous_tyres, current_tyres = previous and previous.tyres or {}, snapshot and snapshot.tyres or {}
    if type(previous_tyres) == "table" and type(current_tyres) == "table" then
      for _, key in ipairs({ "compound", "set_id", "tyre_set_id", "tyre_set" }) do
        if previous_tyres[key] ~= nil and current_tyres[key] ~= nil and previous_tyres[key] ~= current_tyres[key] then
          evidence[#evidence + 1] = { kind = "TYRE_REPLACEMENT", field = key, from = previous_tyres[key], to = current_tyres[key] }
          break
        end
      end
      if number(previous_tyres.reset_counter) and number(current_tyres.reset_counter) and current_tyres.reset_counter > previous_tyres.reset_counter then
        evidence[#evidence + 1] = { kind = "TYRE_RESET", from = previous_tyres.reset_counter, to = current_tyres.reset_counter }
      end
    end
    local function numeric_total(value)
      if number(value) then return value end
      if type(value) ~= "table" then return nil end
      local total, count = 0, 0
      for _, child in pairs(value) do
        local child_total = numeric_total(child)
        if child_total ~= nil then total = total + child_total; count = count + 1 end
      end
      return count > 0 and total or nil
    end
    local previous_damage = numeric_total(previous_car.damage or previous_car.damage_level)
    local current_damage = numeric_total(current_car.damage or current_car.damage_level)
    if previous_damage ~= nil and current_damage ~= nil and current_damage < previous_damage then
      evidence[#evidence + 1] = { kind = "REPAIR_COMPLETION", from = previous_damage, to = current_damage }
    end
    if service_signal(snapshot, { "repair_complete", "repairs_complete", "repair_completed", "repair_confirmed" }) ~= nil then
      evidence[#evidence + 1] = { kind = "REPAIR_COMPLETION" }
    end
    if service_signal(snapshot, { "driver_change_confirmed", "driver_change_completed", "planned_driver_change", "service_confirmed", "planned_service_confirmed", "service_completed" }) ~= nil then
      evidence[#evidence + 1] = { kind = "PLANNED_SERVICE" }
    end
    if service_signal(snapshot, { "manual_new_stint_confirmation", "new_stint_confirmed", "manual_service_confirmation" }) ~= nil then
      evidence[#evidence + 1] = { kind = "MANUAL_NEW_STINT" }
    end
    return evidence
  end

  local function circular_delta(left, right)
    local delta = math.abs(left - right)
    return math.min(delta, 1 - delta)
  end

  local function circular_center(values)
    if #values == 0 then return nil end
    local reference = values[1]
    local total = 0
    for index = 1, #values do
      local value = values[index]
      local delta = value - reference
      if delta > 0.5 then value = value - 1 elseif delta < -0.5 then value = value + 1 end
      total = total + value
    end
    local result = (total / #values) % 1
    if result < 0 then result = result + 1 end
    return result
  end

  local function world_distance(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return nil end
    if not (number(left.x) and number(left.y) and number(left.z) and number(right.x) and number(right.y) and number(right.z)) then return nil end
    local dx, dy, dz = left.x - right.x, left.y - right.y, left.z - right.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  local function new_marker(snapshot)
    local identity = snapshot and snapshot.identity or {}
    return contracts.pit_marker({
      track_layout_key = contracts.track_layout_key(identity),
      track_id = identity.track_id,
      layout_id = identity.layout_id,
      state = "UNAVAILABLE",
      accepted_observations = {},
      rejected_observations = {},
      confidence = 0,
      source = "AUTOMATIC",
      manual_override = false,
      timing = {},
    })
  end

  local function new_visit(snapshot, now_s, started_in_pit)
    local current_car = car(snapshot)
    local evidence = service_evidence(nil, snapshot, 1)
    return {
      started_at_s = now_s,
      started_in_pit = started_in_pit == true,
      entry_snapshot_id = started_in_pit and nil or snapshot.snapshot_id,
      entry_snapshot = started_in_pit and nil or copy(snapshot),
      entry_spline = started_in_pit and nil or current_car.spline,
      entry_world_position = started_in_pit and nil or copy(current_car.world_position),
      box_arrival_s = nil,
      box_departure_s = nil,
      exit_s = nil,
      exit_snapshot = nil,
      reset_suppressed = false,
      movement_m = 0,
      service_evidence = evidence,
      classification = started_in_pit and "UNKNOWN_STOP" or nil,
    }
  end

  local function apply_manual_confirmation(state)
    if state.visit == nil or state.manual_new_stint_confirmation ~= true then return end
    state.visit.service_evidence = state.visit.service_evidence or {}
    state.visit.service_evidence[#state.visit.service_evidence + 1] = { kind = "MANUAL_NEW_STINT" }
    state.manual_new_stint_confirmation = false
  end

  function pit_learning.new(config)
    config = config or {}
    return {
      state = pit_learning.states.ON_TRACK,
      live_pit_lane = false,
      live_pit_box = false,
      previous = nil,
      identity_key = nil,
      marker = nil,
      marker_dirty = false,
      candidate = nil,
      visit = nil,
      suppress_reason = nil,
      sequence = 0,
      events = {},
      max_events = config.max_pit_events or 64,
      max_observations = config.max_pit_observations or 24,
      debounce_s = config.pit_transition_debounce_s or 0.10,
      spline_tolerance = config.pit_spline_cluster_tolerance or 0.025,
      world_jump_m = config.pit_world_jump_threshold_m or 1000,
      movement_limit_m = config.pit_observation_movement_limit_m or 250,
      track_length_m = nil,
      latest_observation = nil,
      latest_rejection = nil,
      last_confirmed_exit = nil,
      service_fuel_jump_l = config.refuel_jump_l or 1,
      manual_new_stint_confirmation = false,
    }
  end

  function pit_learning.set_marker(state, marker, snapshot)
    state.marker = type(marker) == "table" and copy(marker) or nil
    if state.marker == nil then state.marker = new_marker(snapshot or state.previous) end
    state.marker.accepted_observations = state.marker.accepted_observations or {}
    state.marker.rejected_observations = state.marker.rejected_observations or {}
    state.marker.timing = state.marker.timing or {}
    state.marker_dirty = false
    return state.marker
  end

  function pit_learning.manual_override(state, fields)
    local marker = state.marker or new_marker(state.previous)
    for key, value in pairs(fields or {}) do marker[key] = copy(value) end
    marker.schema_version = contracts.schema_versions.pit_marker
    marker.state = "MANUAL_OVERRIDE"
    marker.manual_override = true
    marker.source = "MANUAL_OVERRIDE"
    state.marker = marker
    state.marker_dirty = true
    return marker
  end

  function pit_learning.clear_override(state)
    if state.marker == nil then return false end
    state.marker.manual_override = false
    state.marker.source = "AUTOMATIC"
    local count = #(state.marker.accepted_observations or {})
    state.marker.state = count >= 3 and "CONFIRMED" or count == 2 and "LEARNED" or count == 1 and "PROVISIONAL" or "UNAVAILABLE"
    state.marker_dirty = true
    return true
  end

  local function event(state, snapshot, event_type, payload, confidence, rejection, suppression)
    state.sequence = state.sequence + 1
    local result = contracts.race_event({
      event_id = "pit-event:" .. tostring(state.sequence) .. ":" .. event_type,
      sequence = state.sequence,
      event_type = event_type,
      source_snapshot_id = snapshot and snapshot.snapshot_id or "snapshot:unavailable",
      detection_time_s = snapshot and snapshot.observed_monotonic_s,
      source_time_s = snapshot and snapshot.source_timestamp_s,
      session_time_s = snapshot and snapshot.session and snapshot.session.elapsed_s,
      identity_key = identity_key(snapshot),
      confidence = confidence or "medium",
      provenance = { source = "CSP", detector = "pit-learning-v1" },
      payload = payload or {},
      rejection_reason = rejection,
      suppression_reason = suppression,
    })
    bounded(state.events, result, state.max_events)
    return result
  end

  local function discontinuity(previous, snapshot, state)
    if previous == nil then return nil end
    local old_car, current_car = car(previous), car(snapshot)
    local old_session, current_session = previous.session or {}, snapshot.session or {}
    if identity_key(previous) ~= identity_key(snapshot) then return "IDENTITY_CHANGED" end
    if old_session.replay ~= current_session.replay then return "REPLAY_TRANSITION" end
    if number(old_session.completed_laps) and number(current_session.completed_laps) and current_session.completed_laps < old_session.completed_laps then return "LAP_COUNTER_DECREASE" end
    if number(old_car.reset_counter) and number(current_car.reset_counter) and old_car.reset_counter ~= current_car.reset_counter then return "RESET_COUNTER_CHANGED" end
    if number(old_car.spline) and number(current_car.spline) then
      local delta = math.abs(current_car.spline - old_car.spline)
      if delta > 0.20 and delta < 0.80 then return "SPLINE_JUMP" end
    end
    local spline_delta = number(old_car.spline) and number(current_car.spline) and math.abs(old_car.spline - current_car.spline) or nil
    if world_distance(old_car.world_position, current_car.world_position) and world_distance(old_car.world_position, current_car.world_position) > state.world_jump_m and (spline_delta == nil or spline_delta < 0.80) then return "WORLD_POSITION_JUMP" end
    return nil
  end

  local function marker_values(marker, kind)
    local values = {}
    for index = 1, #(marker.accepted_observations or {}) do
      local observation = marker.accepted_observations[index]
      if observation.kind == kind and number(observation.spline) then values[#values + 1] = observation.spline end
    end
    return values
  end

  local function update_marker(state, snapshot, kind, now_s, observation)
    local marker = state.marker or new_marker(snapshot)
    state.marker = marker
    if marker.manual_override == true then
      state.latest_rejection = "MANUAL_OVERRIDE"
      return false, "MANUAL_OVERRIDE"
    end
    local values = marker_values(marker, kind)
    local center = circular_center(values)
    if center ~= nil and number(observation.spline) and circular_delta(center, observation.spline) > state.spline_tolerance then
      local rejected = copy(observation)
      rejected.reason = "OUTLIER"
      bounded(marker.rejected_observations, rejected, state.max_observations)
      state.latest_rejection = rejected
      if #marker.rejected_observations >= 2 and #values >= 2 then marker.state = "CONFLICTED" end
      state.marker_dirty = true
      return false, "OUTLIER"
    end
    observation.kind = kind
    bounded(marker.accepted_observations, copy(observation), state.max_observations)
    values[#values + 1] = observation.spline
    local updated_center = circular_center(values)
    if kind == "ENTRY" then marker.entry_spline = updated_center; marker.entry_world_position = copy(observation.world_position) end
    if kind == "EXIT" then marker.exit_spline = updated_center; marker.exit_world_position = copy(observation.world_position) end
    marker.confidence = math.min(1, #marker.accepted_observations / 3)
    if #marker.accepted_observations >= 3 then marker.state = "CONFIRMED"
    elseif #marker.accepted_observations == 2 then marker.state = "LEARNED"
    else marker.state = "PROVISIONAL" end
    marker.first_observed_at_s = marker.first_observed_at_s or now_s
    marker.last_observed_at_s = now_s
    marker.source = "AUTOMATIC"
    state.latest_observation = observation
    state.latest_rejection = nil
    state.marker_dirty = true
    return true, nil
  end

  local function make_observation(state, snapshot, kind, now_s, confirmation_state)
    local current_car = car(snapshot)
    local candidate = state.candidate
    local source = candidate and candidate.snapshot or snapshot
    local source_car = car(source)
    return contracts.pit_observation({
      observation_id = "pit-observation:" .. tostring(state.sequence + 1) .. ":" .. kind,
      transition_type = kind,
      source_snapshot_id = source.snapshot_id,
      old_state = kind == "ENTRY" and false or true,
      new_state = kind == "ENTRY" and true or false,
      entry_classification = kind == "ENTRY" and "PIT_LANE_ENTRY" or nil,
      exit_classification = kind == "EXIT" and "PIT_LANE_EXIT" or nil,
      spline = source_car.spline,
      world_position = source_car.world_position,
      reset_counter = source_car.reset_counter,
      speed_kmh = source_car.speed_kmh,
      source_time_s = source.source_timestamp_s,
      detection_time_s = source.observed_monotonic_s,
      stability_duration_s = candidate and math.max(0, now_s - candidate.at_s) or 0,
      movement_m = world_distance(source_car.world_position, current_car.world_position),
      confidence = confirmation_state == "CONFIRMED" and "high" or "medium",
      confirmation_state = confirmation_state or "PROVISIONAL",
      rejection_reasons = {},
    })
  end

  local function credible(state, snapshot, kind, now_s)
    local candidate = state.candidate
    if state.suppress_reason ~= nil then return false, state.suppress_reason end
    if candidate == nil then return false, "CANDIDATE_MISSING" end
    if identity_key(candidate.snapshot) ~= identity_key(snapshot) then return false, "IDENTITY_CHANGED" end
    local old_reset, new_reset = car(candidate.snapshot).reset_counter, car(snapshot).reset_counter
    if number(old_reset) and number(new_reset) and old_reset ~= new_reset then return false, "RESET_COUNTER_CHANGED" end
    local movement = world_distance(car(candidate.snapshot).world_position, car(snapshot).world_position)
    if movement ~= nil and movement > state.movement_limit_m then return false, "WORLD_POSITION_JUMP" end
    if now_s - candidate.at_s < state.debounce_s then return false, "STABILITY_PENDING" end
    if kind == "ENTRY" and not pit_lane(snapshot) then return false, "CANDIDATE_INTERRUPTED" end
    if kind == "EXIT" and pit_lane(snapshot) then return false, "CANDIDATE_INTERRUPTED" end
    return true, nil
  end

  local function finalize_candidate(state, snapshot, now_s, kind)
    local credible_result, reason = credible(state, snapshot, kind, now_s)
    if not credible_result then
      if reason ~= "STABILITY_PENDING" then
        local rejected = make_observation(state, snapshot, kind, now_s, "REJECTED")
        rejected.rejection_reasons = { reason }
        if state.marker ~= nil then bounded(state.marker.rejected_observations, rejected, state.max_observations); state.marker_dirty = true end
        state.latest_rejection = rejected
        state.candidate = nil
        event(state, snapshot, kind == "ENTRY" and "PIT_ENTRY_REJECTED" or "PIT_EXIT_REJECTED", { reason = reason }, "low", reason, state.suppress_reason)
      else
        return nil
      end
      return false
    end
    local observation = make_observation(state, snapshot, kind, now_s, "CONFIRMED")
    local accepted, rejection = update_marker(state, snapshot, kind, now_s, observation)
    observation.confirmation_state = accepted and "CONFIRMED" or "REJECTED"
    state.candidate = nil
    local emitted = event(state, snapshot, kind == "ENTRY" and (accepted and "PIT_ENTRY_CONFIRMED" or "PIT_ENTRY_REJECTED") or (accepted and "PIT_EXIT_CONFIRMED" or "PIT_EXIT_REJECTED"), { observation = observation, marker_state = state.marker and state.marker.state }, accepted and "high" or "low", rejection, state.suppress_reason)
    return accepted
  end

  local function complete_visit(state, snapshot, now_s)
    local visit = state.visit
    if visit == nil then return end
    visit.exit_snapshot = copy(snapshot)
    visit.exit_s = now_s
    if visit.entry_snapshot == nil or visit.started_in_pit == true or visit.reset_suppressed then
      visit.classification = "UNKNOWN_STOP"
      visit.classification_reason = "ENTRY_OR_RESET_UNTRUSTWORTHY"
    elseif #(visit.service_evidence or {}) > 0 then
      visit.classification = "SERVICE_STOP"
      visit.classification_reason = "CONFIRMED_SERVICE_EVIDENCE"
    elseif visit.box_arrival_s == nil then
      visit.classification = "DRIVE_THROUGH"
      visit.classification_reason = "NO_PIT_BOX_ARRIVAL"
    elseif visit.box_departure_s == nil then
      visit.classification = "UNKNOWN_STOP"
      visit.classification_reason = "PIT_BOX_STATE_INCOMPLETE"
    else
      visit.classification = "STOP_GO"
      visit.classification_reason = "PIT_BOX_WITHOUT_SERVICE_EVIDENCE"
    end
    visit.total_lane_duration_s = math.max(0, (visit.exit_s or now_s) - visit.started_at_s)
    if visit.box_arrival_s ~= nil and visit.box_departure_s ~= nil then
      visit.service_duration_s = math.max(0, visit.box_departure_s - visit.box_arrival_s)
    end
    local timing = state.marker and state.marker.timing or nil
    if timing ~= nil then
      timing.last_classification = visit.classification
      timing.last_total_lane_duration_s = visit.total_lane_duration_s
      timing.last_service_duration_s = visit.service_duration_s
      timing.last_entry_to_box_s = visit.box_arrival_s and visit.box_arrival_s - visit.started_at_s or nil
      timing.last_box_to_exit_s = visit.box_departure_s and visit.exit_s - visit.box_departure_s or nil
      state.marker_dirty = true
    end
    state.last_visit = copy(visit)
    state.visit = nil
  end

  function pit_learning.update(state, snapshot, now_s)
    if type(snapshot) ~= "table" then return state end
    state.last_confirmed_exit = nil
    local current_car = car(snapshot)
    local previous = state.previous
    local previous_car = car(previous)
    local current_lane = pit_lane(snapshot)
    local current_box = pit_box(snapshot)
    local was_lane = pit_lane(previous)
    local was_box = pit_box(previous)
    local reason = discontinuity(previous, snapshot, state)
    if reason ~= nil then
      state.suppress_reason = reason
      state.state = pit_learning.states.RESET_SUPPRESSED
      if state.visit ~= nil then state.visit.reset_suppressed = true end
      if state.candidate ~= nil then state.candidate = nil end
      event(state, snapshot, "PIT_LEARNING_SUPPRESSED", { reason = reason }, "high", nil, reason)
    end

    if previous == nil then
      state.identity_key = identity_key(snapshot)
      state.live_pit_lane = current_lane
      state.live_pit_box = current_box
      if current_lane then
        state.visit = new_visit(snapshot, now_s, true)
        apply_manual_confirmation(state)
        state.state = current_box and pit_learning.states.AT_PIT_BOX or pit_learning.states.IN_PIT_LANE
      else
        state.state = pit_learning.states.ON_TRACK
      end
      state.marker = state.marker or new_marker(snapshot)
      state.previous = copy(snapshot)
      return state
    end

    if current_lane ~= was_lane then
      state.live_pit_lane = current_lane
      if current_lane then
        state.candidate = { kind = "ENTRY", snapshot = copy(snapshot), at_s = now_s }
        state.visit = new_visit(snapshot, now_s, false)
        apply_manual_confirmation(state)
        state.state = pit_learning.states.ENTRY_CANDIDATE
        event(state, snapshot, "PIT_ENTRY_CANDIDATE", { original_snapshot_id = snapshot.snapshot_id }, "low")
        -- The driver-facing fact is immediate; confidence only controls the
        -- calibration event and marker update.
        state.state = pit_learning.states.IN_PIT_LANE
      else
        state.candidate = { kind = "EXIT", snapshot = copy(snapshot), at_s = now_s }
        state.live_pit_lane = false
        state.state = pit_learning.states.EXIT_CANDIDATE
        event(state, snapshot, "PIT_EXIT_CANDIDATE", { original_snapshot_id = snapshot.snapshot_id }, "low")
      end
    end

    if current_box ~= was_box then
      if current_box then
        if state.visit == nil then state.visit = new_visit(snapshot, now_s, true) end
        apply_manual_confirmation(state)
        state.visit.box_arrival_s = now_s
        state.state = pit_learning.states.AT_PIT_BOX
        event(state, snapshot, "PIT_BOX_ARRIVAL", { service_start_s = now_s }, "medium")
      else
        if state.visit ~= nil then state.visit.box_departure_s = now_s end
        if current_lane then state.state = pit_learning.states.LEAVING_PIT_BOX end
        event(state, snapshot, "PIT_BOX_DEPARTURE", { service_end_s = now_s }, "medium")
      end
    end
    if state.visit ~= nil then
      local evidence = service_evidence(previous, snapshot, state.service_fuel_jump_l)
      for index = 1, #evidence do state.visit.service_evidence[#state.visit.service_evidence + 1] = evidence[index] end
    end

    if state.candidate ~= nil then
      local kind = state.candidate.kind
      if kind == "ENTRY" and current_lane then finalize_candidate(state, snapshot, now_s, kind)
      elseif kind == "EXIT" and not current_lane then
        local accepted = finalize_candidate(state, snapshot, now_s, kind)
        if accepted ~= nil then
          state.state = pit_learning.states.BACK_ON_TRACK
          complete_visit(state, snapshot, now_s)
          if state.last_visit and state.last_visit.classification == "SERVICE_STOP" then
            state.last_confirmed_exit = event(state, snapshot, "PIT_SERVICE_STOP_CONFIRMED", { classification = "SERVICE_STOP", visit = copy(state.last_visit) }, "high")
          end
          state.suppress_reason = nil
        end
      elseif kind == "ENTRY" and not current_lane then
        finalize_candidate(state, snapshot, now_s, kind)
        state.state = pit_learning.states.BACK_ON_TRACK
        state.visit = nil
      end
    elseif not current_lane then
      state.state = state.suppress_reason and pit_learning.states.RESET_SUPPRESSED or pit_learning.states.ON_TRACK
      if was_lane and state.visit ~= nil then complete_visit(state, snapshot, now_s) end
      if state.suppress_reason ~= nil then state.suppress_reason = nil end
    elseif current_box then
      state.state = pit_learning.states.AT_PIT_BOX
    else
      state.state = state.suppress_reason and pit_learning.states.RESET_SUPPRESSED or pit_learning.states.IN_PIT_LANE
    end

    state.live_pit_lane = current_lane
    state.live_pit_box = current_box
    state.identity_key = identity_key(snapshot)
    state.track_length_m = snapshot.session and snapshot.session.track_length_m or state.track_length_m
    state.previous = copy(snapshot)
    return state
  end

  function pit_learning.confirm_new_stint(state)
    if state.visit == nil then
      state.manual_new_stint_confirmation = true
      return false
    end
    state.visit.service_evidence = state.visit.service_evidence or {}
    state.visit.service_evidence[#state.visit.service_evidence + 1] = { kind = "MANUAL_NEW_STINT" }
    return true
  end

  function pit_learning.forward_distance(current_spline, target_spline, track_length_m)
    if not (number(current_spline) and number(target_spline) and number(track_length_m) and track_length_m > 0 and current_spline >= 0 and current_spline < 1 and target_spline >= 0 and target_spline < 1) then
      return nil, "PIT_ENTRY_NOT_CALIBRATED"
    end
    local delta = (target_spline - current_spline + 1) % 1
    return delta * track_length_m, delta > (target_spline - current_spline) and "PIT_ENTRY_WRAPAROUND_APPLIED" or "MEASURED_CURRENT"
  end

  function pit_learning.distance_to_entry(state, snapshot)
    local marker = state and state.marker or nil
    local current_car = car(snapshot)
    local track_length = snapshot and snapshot.session and snapshot.session.track_length_m or state and state.track_length_m
    if marker == nil or marker.entry_spline == nil then return nil, "PIT_ENTRY_NOT_CALIBRATED" end
    return pit_learning.forward_distance(current_car.spline, marker.entry_spline, track_length)
  end

  function pit_learning.calibration(state, snapshot)
    local marker = state and state.marker or nil
    if marker == nil or marker.entry_spline == nil then return nil end
    local identity = snapshot and snapshot.identity or {}
    return {
      track_id = identity.track_id,
      layout_id = identity.layout_id,
      track_length_m = snapshot and snapshot.session and snapshot.session.track_length_m,
      pit_entry_spline = marker.entry_spline,
      pit_route_additional_m = marker.timing and marker.timing.route_additional_m,
      source = marker.source,
      validation_status = marker.state,
    }
  end

  function pit_learning.diagnostics(state, snapshot)
    local distance, distance_reason = pit_learning.distance_to_entry(state, snapshot)
    return {
      state = state.state,
      live_pit_lane = state.live_pit_lane,
      live_pit_box = state.live_pit_box,
      marker = state.marker,
      marker_state = state.marker and state.marker.state or "UNAVAILABLE",
      confidence = state.marker and state.marker.confidence or 0,
      accepted_observations = state.marker and #(state.marker.accepted_observations or {}) or 0,
      rejected_observations = state.marker and #(state.marker.rejected_observations or {}) or 0,
      distance_to_entry_m = distance,
      distance_reason = distance_reason,
      latest_observation = state.latest_observation,
      latest_rejection = state.latest_rejection,
      last_confirmed_exit = state.last_confirmed_exit,
      current_visit = state.visit,
      last_visit = state.last_visit,
      suppress_reason = state.suppress_reason,
      marker_dirty = state.marker_dirty,
    }
  end

  namespace.live.pit_learning = pit_learning
end
