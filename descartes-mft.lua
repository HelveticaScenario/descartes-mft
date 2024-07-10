-- Descartes MFT
-- A seqencer inspired by the
-- Make Noise Rene for use with
-- the Midi Fighter Twister controller

inspect = include 'lib/inspect'

-- engine.name = 'PolyPerc'

g = grid.connect()
local MIN_VOLTS = -5
local MAX_VOLTS = 10
local MIN_SEPARATION = 0.005

function cc_to_x_y(cc)
  return cc % 4, math.floor(cc/4)
end

function normalize_cc(val)
  return val / 127
end

local shapes = {'linear', 'sine', 'logarithmic', 'exponential', 'now', 'wait', 'over', 'under', 'rebound'}
local options = {"Volts", "Pulse", "Envelope"}
local volts_params = {"volts_min_", "volts_max_", "volts_slew_", "volts_shape_"}
local pulse_params = {"pulse_level_", "pulse_time_max_"}
local envelope_params = {}

update_id = nil
function update()
  started = true
  update_id = nil
  for i = 1, 4 do
    local mode = params:get('mode_'..i)
    local entry = outs[i][get_note_idx(
      position[1],
      position[2]
    )]
    local val = entry.val
    local enabled = entry.enabled

    if enabled == 1 then
      if options[mode] == "Volts" then
        local min = params:get(volts_params[1]..i)
        local max = params:get(volts_params[2]..i)
        local slew = params:get(volts_params[3]..i)
        local shape = shapes[params:get(volts_params[4]..i)]
        crow.output[i].shape = shape
        crow.output[i].slew = slew
        crow.output[i].volts = normalize_cc(val) * (max - min) + min
  
      elseif options[mode] == "Pulse" then
        local level = params:get(pulse_params[1]..i)
        local time_max = params:get(pulse_params[2]..i)
        crow.output[i].slew = 0
        crow.output[i].volts = 0
        crow.output[i].action = 'pulse(' .. (normalize_cc(val) * time_max) .. ',' .. level .. ')'
        crow.output[i]()
      elseif options[mode] == "Envelope" then
  
      end
    end
  end
  redraw()
  
end

function update_sleep ()
  clock.sleep(0.004)
  update()
end


function process_change(n)
  if started then
    local prev = position[n]
    position[n] = (prev + 1) % 4
  end
  if update_id ~= nil then
    clock.cancel(update_id)
    update()
  else
    update_id = clock.run(update_sleep)
  end
end


function get_note_idx(x, y)
  return ((x * 4) + y) + 1
end

function handle_turn(cc, val)
  local x, y = cc_to_x_y(cc)
  local idx = get_note_idx(x, y)
  outs[page][idx].val = val
  params:set('value_'..page..'_'..idx, val)
  cursor = {x + 1, y + 1}
  redraw()
end

function handle_push(cc, state)
  if state == true then
    return
  end
  local x, y = cc_to_x_y(cc)
  local idx = get_note_idx(x, y)
  local enabled = outs[page][idx].enabled ~ 1
  outs[page][idx].enabled =  enabled
  params:set('enabled_'..page..'_'..idx, enabled)
  redraw_midi()
end

function handle_side(cc, state)
  if state == true then
    return
  end
  if cc == 8 then
    page = 1
    refresh_page()
    redraw()
  elseif cc == 11 then
    page = 2
    refresh_page()
    redraw()
  elseif cc == 10 then
    page = 3
    refresh_page()
    redraw()
  elseif cc == 13 then
    page = 4
    refresh_page()
    redraw()
  end
end

function handle_midi_msg(msg)
  if msg.ch == 1 then
    handle_turn(msg.cc, msg.val)
  elseif msg.ch == 2  then
    handle_push(msg.cc, msg.val == 127)
  elseif msg.ch == 4 then
    handle_side(msg.cc, msg.val == 127)
  end
end


colors = {0, 32, 64, 85}

function refresh_page()
  for i = 0, 15 do
    m:cc(i, outs[page][get_note_idx(i % 4, math.floor(i / 4))].val, 1)
    m:cc(i, colors[page], 2)
  end
end


function init()
  -- initialization
  started = false
  position = {0, 0}
  cursor = {1, 1}
  page = 1

  save_enable = false
  init_params()

  params:read(norns.state.data .. '_autosave.pset')
  params:bang()
  save_enable = true


  outs = {}
  for p = 1, 4 do
    outs[p] = {}
    for i=1, 16 do
      local val_id = 'value_'..p..'_'..i
      local enabled_id = 'enabled_'..p..'_'..i

      outs[p][i] = {val = params:get(val_id), enabled = params:get(enabled_id)}
    end
  end

  for index, value in ipairs(midi.vports) do
    if util.string_starts(value.name, "Midi Fighter Twister") then
      m = midi.connect(index)
      break
    end
  end

  m.event = function (data)
    handle_midi_msg(midi.to_msg(data))
  end

  refresh_page()
  for i = 1, 16 do
    m:cc(i-1, 32, 3)
  end

  for i=1,2 do
    crow.input[i].change = function () process_change(i) end
    crow.input[i].mode("change", 2.0, 0.25, "rising")
  end

 
  redraw()
end

save_enable = false
function save()
  if save_enable then
    params:write(norns.state.data .. '_autosave.pset')
  end
end

function init_params()
  params:add_separator("Rene")
  for i = 1, 4 do
    function rebuild(idx)
      for _, p in ipairs({volts_params, pulse_params, envelope_params}) do
        for _, value in ipairs(p) do
          params:hide(value..i)
        end
      end

      local selected_params = {}
      if options[idx] == 'Volts' then
        selected_params = volts_params
      elseif  options[idx] == 'Pulse' then
        selected_params = pulse_params
      elseif options[idx] == 'Envelope' then
        selected_params = envelope_params
      end

      for _, value in ipairs(selected_params) do
        params:show(value..i)
      end

      _menu.rebuild_params()

      save()
    end

    params:add_group("Output "..i, #volts_params + #pulse_params + #envelope_params + 1)

    params:add_option('mode_'..i, "Mode", options, 1)
    params:set_action('mode_'..i, rebuild)

    params:add_control(volts_params[1]..i, "Min Volts", controlspec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0, 0, 'V', MIN_SEPARATION))
    params:set_action(volts_params[1]..i, function(value)
        if params:get(volts_params[2]..i) < value + MIN_SEPARATION then
            params:set(volts_params[2]..i, value + MIN_SEPARATION)
        end
        save()
    end)

    params:add_control(volts_params[2]..i, "Max Volts", controlspec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0, 5, 'V', MIN_SEPARATION))
    params:set_action(volts_params[2]..i, function(value)
        if params:get(volts_params[1]..i) > value - MIN_SEPARATION then
            params:set(volts_params[1]..i, value - MIN_SEPARATION)
        end
        save()
    end)

    params:add_control(volts_params[3]..i, "Slew Time", controlspec.new(0, 10, "lin", 0, 0, 'S', 0.005))
    params:set_action(volts_params[3]..i, save)
    
    params:add_option(volts_params[4]..i, "Shape", shapes, 1)
    params:set_action(volts_params[4]..i, save)
    
    
    params:add_control(pulse_params[1]..i, "Level", controlspec.new(0, 10, "lin", MIN_SEPARATION, 5, 'V'))
    params:set_action(pulse_params[1]..i, save)

    params:add_control(pulse_params[2]..i, "Max Time", controlspec.new(0, 10, "lin", 0, 1, 'S', 0.005))
    params:set_action(pulse_params[2]..i, save)
  end
  params:add_separator()
  params:add_trigger('reset_to_default', 'Reset Params')
  params:set_action('reset_to_default', function ()
    save_enable = false
    for _,v in pairs(params.params) do
      v:set_default()
    end

    for p = 1, 4 do
      for i=1, 16 do
        local val_id = 'value_'..p..'_'..i
        local enabled_id = 'enabled_'..p..'_'..i
        outs[p][i] = {val = params:get(val_id), enabled = params:get(enabled_id)}
      end
    end

    refresh_page()
    redraw()

    save_enable = true
    save()
  end)

  for p = 1, 4 do
    for i = 1, 16 do
      local id = 'value_'..p..'_'..i
      params:add_number(id, id, 0, 127, 0)
      params:set_action(id, save)
      params:hide(id)

      id = 'enabled_'..p..'_'..i
      params:add_binary(id, id, 'toggle', 1)
      params:set_action(id, save)
      params:hide(id)
    end
  end
end


function grid_redraw()
  g:all(0)
  for x=1, 4 do
    for y=1, 4 do
      g:led(x, y, 2)
    end
  end 
  local cur = cursor
  local pos = position
  g:led(cur[1], cur[2], 4)
  g:led(pos[1] + 1, pos[2] + 1, 15)
  g:refresh()
end

g.key = function (x, y, state)
  if x >= 1 and x <= 4 and y >= 1 and y <= 4 then
    cursor = {x, y}
    redraw()
  end
end


function key(n,z)
  -- key actions: n = number, z = state
  if n == 2 and z == 0 then
    position = {0, 0}
    started = false
    redraw()
  end
end

function enc(n, d)
  -- encoder actions: n = number, d = delta
  if n == 2 then
    local idx = get_note_idx(cursor[1] - 1, cursor[2] - 1)
    local note = outs[page][idx].val
    note = note + d
    outs[page][idx].val = math.max(0, math.min(127, note))
    refresh_page()
    redraw()
  end
end

function redraw_midi()
  for x = 0, 3 do
    for y = 0, 3 do
      if position[1] == x and position[2] == y then
        m:cc((y * 4) + x, 47, 3)
      elseif outs[page][get_note_idx(x, y)].enabled ~= 1 then
        m:cc((y * 4) + x, 20, 3)
      else
        m:cc((y * 4) + x, 32, 3)
      end
    end
  end
end

function redraw()
  screen.clear()
  screen.stroke()
  screen.level(15)
  for x = 1, 4 do
    for y = 1, 4 do

      screen.line_width(1)
      local cen_x, cen_y = (x * 15) - 6, (y * 15) - 6

      screen.circle(cen_x, cen_y, 6)
      screen.level(5)
      screen.stroke()


      
      if x == cursor[1] and y == cursor[2] then
        screen.circle(cen_x, cen_y, 3)
        screen.fill()
      end

      screen.level(15)
      if x == (position[1] + 1) and y == (position[2] + 1) then
        screen.circle(cen_x, cen_y, 3)
        screen.fill()
      end

      local note = (outs[page][get_note_idx(x - 1, y - 1)].val / 127 * 0.9 + 0.05) * 2 * math.pi
      
      screen.move(cen_x, cen_y)
      screen.line_width(2)
      screen.line_rel(math.sin(note) * 8 * -1, math.cos(note) * 8)
      screen.stroke()
    end
  end

  screen.move(75, 30)
  screen.text('sel:')
  screen.move(92, 30)
  screen.text(outs[page][get_note_idx(cursor[1] - 1, cursor[2] - 1)].val / 127 * 5 .. " volts" )
  screen.move(75, 40)
  screen.text('cur:')
  screen.move(92, 40)
  screen.text(outs[page][get_note_idx(position[1], position[2])].val / 127 * 5 .. " volts" )



  screen.update()
  redraw_midi()
  grid_redraw()
end

function cleanup()
  -- deinitialization
end