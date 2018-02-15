local ATTACHED = false -- Should wires in the air be dropped?

wires = {}

local finite_stacks = (not minetest.setting_getbool("creative_mode")) or (minetest.get_modpath("unified_inventory") ~= nil)

dofile(minetest.get_modpath("wires").."/wires_tables.lua")

local function old_mesecon_addPosRule(p, r)
	return {x = p.x + r.x, y = p.y + r.y, z = p.z + r.z}
end

local function old_mesecon_update_autoconnect(pos, secondcall, replace_old)
	local xppos = {x=pos.x+1, y=pos.y, z=pos.z}
	local zppos = {x=pos.x, y=pos.y, z=pos.z+1}
	local xmpos = {x=pos.x-1, y=pos.y, z=pos.z}
	local zmpos = {x=pos.x, y=pos.y, z=pos.z-1}

	local xpympos = {x=pos.x+1, y=pos.y-1, z=pos.z}
	local zpympos = {x=pos.x, y=pos.y-1, z=pos.z+1}
	local xmympos = {x=pos.x-1, y=pos.y-1, z=pos.z}
	local zmympos = {x=pos.x, y=pos.y-1, z=pos.z-1}

	local xpypos = {x=pos.x+1, y=pos.y+1, z=pos.z}
	local zpypos = {x=pos.x, y=pos.y+1, z=pos.z+1}
	local xmypos = {x=pos.x-1, y=pos.y+1, z=pos.z}
	local zmypos = {x=pos.x, y=pos.y+1, z=pos.z-1}

	if secondcall == nil then
		old_mesecon_update_autoconnect(xppos, true)
		old_mesecon_update_autoconnect(zppos, true)
		old_mesecon_update_autoconnect(xmpos, true)
		old_mesecon_update_autoconnect(zmpos, true)

		old_mesecon_update_autoconnect(xpypos, true)
		old_mesecon_update_autoconnect(zpypos, true)
		old_mesecon_update_autoconnect(xmypos, true)
		old_mesecon_update_autoconnect(zmypos, true)

		old_mesecon_update_autoconnect(xpympos, true)
		old_mesecon_update_autoconnect(zpympos, true)
		old_mesecon_update_autoconnect(xmympos, true)
		old_mesecon_update_autoconnect(zmympos, true)
	end

	nodename = minetest.env:get_node(pos).name
	if string.find(nodename, "mesecons:wire_") == nil and not replace_old then return nil end

	if mesecon:rules_link_anydir(pos, xppos) then xp = 1 else xp = 0 end
	if mesecon:rules_link_anydir(pos, xmpos) then xm = 1 else xm = 0 end
	if mesecon:rules_link_anydir(pos, zppos) then zp = 1 else zp = 0 end
	if mesecon:rules_link_anydir(pos, zmpos) then zm = 1 else zm = 0 end

	if mesecon:rules_link_anydir(pos, xpympos) then xp = 1 end
	if mesecon:rules_link_anydir(pos, xmympos) then xm = 1 end
	if mesecon:rules_link_anydir(pos, zpympos) then zp = 1 end
	if mesecon:rules_link_anydir(pos, zmympos) then zm = 1 end

	if mesecon:rules_link_anydir(pos, xpypos) then xpy = 1 else xpy = 0 end
	if mesecon:rules_link_anydir(pos, zpypos) then zpy = 1 else zpy = 0 end
	if mesecon:rules_link_anydir(pos, xmypos) then xmy = 1 else xmy = 0 end
	if mesecon:rules_link_anydir(pos, zmypos) then zmy = 1 else zmy = 0 end

	if xpy == 1 then xp = 1 end
	if zpy == 1 then zp = 1 end
	if xmy == 1 then xm = 1 end
	if zmy == 1 then zm = 1 end

	local nodeid = 	tostring(xp )..tostring(zp )..tostring(xm )..tostring(zm )..
			tostring(xpy)..tostring(zpy)..tostring(xmy)..tostring(zmy)


	if string.find(nodename, "_off") ~= nil then
		minetest.env:set_node(pos, {name = "mesecons:wire_"..nodeid.."_off"})
	else
		minetest.env:set_node(pos, {name = "mesecons:wire_"..nodeid.."_on" })
	end
end

local function hash_sides(sides)
	local n = 0
	for _, side in ipairs(sides.sides) do
		n = n + 2^side
	end
	for _, connects in ipairs(sides.connects) do
		n = n + 2^(6*connects[1]+connects[2]+6)
	end
	return n
end

local function dehash_sides(hash)
	local sides = {sides = {}, connects = {}}
	for i = 0, 5 do
		if hash%2 == 1 then
			sides.sides[#sides.sides+1] = i
		end
		hash = math.floor(hash/2)
	end
	for i = 0, 5 do
		for j = 0, 5 do
			if hash%2 == 1 then
				sides.connects[#sides.connects+1] = {i, j}
			end
			hash = math.floor(hash/2)
		end
	end
	return sides
end

local function dir_to_side(dir)
	local a = dir.x + 2*dir.y + 3*dir.z
	if a > 0 then
		return a - 1
	else
		return 2 - a
	end
end

local function side_to_dir(side)
	return ({{x = 1, y = 0, z = 0},
		{x = 0, y = 1, z = 0},
		{x = 0, y = 0, z = 1},
		{x = -1, y = 0, z = 0},
		{x = 0, y = -1, z = 0},
		{x = 0, y = 0, z = -1}})[side+1]
end

local function rotate_side(side, facedir)
	return wires.rotated_sides[facedir*6+side+1]
end

local function rotate_sides(sides, facedir)
	local s = {}
	for _, side in ipairs(sides.sides) do
		s[#s+1] = rotate_side(side, facedir)
	end
	local c = {}
	for _, connect in ipairs(sides.connects) do
		c[#c+1] = {rotate_side(connect[1], facedir), rotate_side(connect[2], facedir)}
	end
	return {sides = s, connects = c}
end

local nodeboxes_sides = {}
for i = 0, 5 do
	local nb = {-1/16, -1/16, -1/16, 1/16, 1/16, 1/16}
	if i >= 3 then
		nb[(i%3)+1] = -1/2
		nb[(i%3)+4] = -1/2 + 1/16
	else
		nb[(i%3)+1] = 1/2 - 1/16
		nb[(i%3)+4] = 1/2
	end
	nodeboxes_sides[i] = nb
end

local nodeboxes_bumps = {}
for i = 0, 5 do
	local nb = {-2/16, -2/16, -2/16, 2/16, 2/16, 2/16}
	if i >= 3 then
		nb[(i%3)+1] = -1/2
		nb[(i%3)+4] = -1/2 + 4/32
	else
		nb[(i%3)+1] = 1/2 - 4/32
		nb[(i%3)+4] = 1/2
	end
	nodeboxes_bumps[i] = nb
end

local selectionboxes_sides = {}
for i = 0, 5 do
	local nb = {-1/2, -1/2, -1/2, 1/2, 1/2, 1/2}
	if i >= 3 then
		nb[(i%3)+4] = -1/2 + 3/16
	else
		nb[(i%3)+1] = 1/2 - 3/16
	end
	selectionboxes_sides[i] = nb
end

local function copy_table(tbl)
	local tbl2 = {}
	for key, val in pairs(tbl) do
		tbl2[key] = val
	end
	return tbl2
end

local nodeboxes_connects = {}
for i = 0, 5 do
	for j = 0, 5 do
		local nb = copy_table(nodeboxes_sides[i])
		if j >= 3 then
			nb[(j%3)+1] = -1/2-1/16
		else
			nb[(j%3)+4] = 1/2+1/16
		end
		nodeboxes_connects[6*i+j] = nb
	end
end

local function in_table(tbl, n)
	for _, i in ipairs(tbl) do
		if i == n then return true end
	end
	return false
end

local function is_side_in_pos(pos, side, otherside)
	local node = minetest.get_node(pos)
	local meta = minetest.get_meta(pos)
	if string.find(node.name, "wires:wire")==nil then return nil end
	if meta:get_int("noconnect"..side..otherside)==1 then return false end
	local hash = minetest.registered_nodes[node.name].basename
	local sides = dehash_sides(hash)
	sides = rotate_sides(sides, node.param2)
	local it = in_table(sides.sides, side)
	if it then return true else return nil end
end

local function minmax(a, b)
	return {x = math.max(a, b)+2, y = math.min(a, b)+2, z = 0}
end

local function get_rule(s, rule)
	rule.sx = s.x
	rule.sy = s.y
	rule.sz = s.z
	return rule
end

local function get_all_rules(node)
	local t = {}
	if mesecon:is_conductor(node.name) then
		t[#t+1] = mesecon:conductor_get_rules(node)
	end
	if mesecon:is_receptor(node.name) then
		t[#t+1] = mesecon:receptor_get_rules(node)
	end
	if mesecon:is_effector(node.name) then
		t[#t+1] = mesecon:effector_get_rules(node)
	end
	if t[1] ~= nil then
		return mesecon:flattenrules(t)
	end
	return nil
end

local function should_connect(pos, s, side, fromside, r)
	local other = old_mesecon_addPosRule(pos, r)
	local s_in_pos = is_side_in_pos(other, side, fromside)
	if s_in_pos ~= nil then return s_in_pos end
	local rule = get_rule(s, r)
	local othernode = minetest.get_node(other)
	local otherrules = get_all_rules(othernode)
	if not otherrules then return false end
	for _, orule in ipairs(mesecon:flattenrules(otherrules)) do
		if mesecon:cmpPos(old_mesecon_addPosRule(other, orule), pos) then
			if orule.sx == nil or
				(orule.sx == rule.sx and orule.sy == rule.sy
					and orule.sz == rule.sz) then
				return true
			end
		end
	end
end

local function calculate_connects(sides, pos)
	local meta = minetest.get_meta(pos)
	sides.connects = {}
	for _, side in ipairs(sides.sides) do
		for toside = 0, 5 do
		if side%3 ~= toside%3 then
			--if in_table(sides.sides, toside) or is_side_in_pos(vector.add(pos, side_to_dir(toside)), side)
			--		or is_side_in_pos(vector.add(pos, vector.add(side_to_dir(side), side_to_dir(toside))), (toside+3)%6) then
			if in_table(sides.sides, toside) or (meta:get_int("noconnect"..side..toside)~=1 and (should_connect(pos, side_to_dir(side), side, (toside+3)%6, side_to_dir(toside)) or should_connect(pos, minmax(side, (toside+3)%6), (toside+3)%6, (side+3)%6, vector.add(side_to_dir(toside), side_to_dir(side))))) then
				sides.connects[#sides.connects+1] = {side, toside}
			end
		end
		end
	end
end

local function swap_node(pos, oldnode, newnode)
	local meta = minetest.get_meta(pos)
	local meta0 = meta:to_table()
	minetest.set_node(pos, {name = "air"})
	mesecon.on_dignode(pos, oldnode)
	minetest.set_node(pos, newnode)
	meta = minetest.get_meta(pos)
	meta:from_table(meta0)
	mesecon.on_placenode(pos, newnode)
end

local function update_connection(pos)
	local node = minetest.get_node(pos)
	if string.find(node.name, "wires:wire") == nil or minetest.registered_nodes[node.name] == nil then return end
	local sides = dehash_sides(minetest.registered_nodes[node.name].basename)
	sides = rotate_sides(sides, node.param2)
	calculate_connects(sides, pos)
	local hash = hash_sides(sides)
	local nodename = "wires:wire_off_"..wires.wires[hash]
	local param2 = wires.wire_facedirs[hash]
	swap_node(pos, node, {name = nodename, param2 = param2})
end

local function update_connections(pos)
	for x = -1, 1 do
	for y = -1, 1 do
	for z = -1, 1 do
		if math.abs(x)+math.abs(y)+math.abs(z) <= 2 then
			update_connection({x = pos.x+x, y = pos.y+y, z = pos.z+z})
		end
	end
	end
	end
end

local function get_rules(node)
	local hash = minetest.registered_nodes[node.name].basename
	local sides = dehash_sides(hash)
	sides = rotate_sides(sides, node.param2)
	local rules = {}
	for _, c in ipairs(sides.connects) do
		rules[#rules+1] = get_rule(side_to_dir(c[1]), side_to_dir(c[2]))
		rules[#rules+1] = get_rule(minmax((c[2]+3)%6, c[1]), vector.add(side_to_dir(c[2]), side_to_dir(c[1])))
	end
	return rules
end

local function get_rules2(node)
	local hash = minetest.registered_nodes[node.name].basename
	local sides = dehash_sides(hash)
	sides = rotate_sides(sides, node.param2)
	local rules = {{}, {}}
	for _, c in ipairs(sides.connects) do
		local index = 1
		if c[1] == sides.sides[2] then index = 2 end
		rules[index][#rules[index]+1] = get_rule(side_to_dir(c[1]), side_to_dir(c[2]))
		rules[index][#rules[index]+1] = get_rule(minmax((c[2]+3)%6, c[1]), vector.add(side_to_dir(c[2]), side_to_dir(c[1])))
	end
	return rules
end

local function update_table(up, tbl)
	for key, val in pairs(up) do
		tbl[key] = val
	end
	return tbl
end

local function place_wire(itemstack, placer, pointed_thing)
	if pointed_thing.type ~= "node" then return end
	local dir = vector.subtract(pointed_thing.under, pointed_thing.above)
	local onto = minetest.get_node(pointed_thing.under)
	if string.find(onto.name, "wires:wire") ~= nil and minetest.registered_nodes[onto.name] then
		local h = minetest.registered_nodes[onto.name].basename
		local sds = rotate_sides(dehash_sides(h), onto.param2).sides
		if #sds == 1 and sds[1]%3 ~= dir_to_side(dir)%3 then
			dir = side_to_dir(sds[1])
			pointed_thing.under = vector.add(dir, pointed_thing.above)
			onto = minetest.get_node(pointed_thing.under)
		end
	end
	if ATTACHED and (onto.name == "air" or string.find(onto.name, "wires:wire")) then return end
	local node = minetest.get_node(pointed_thing.above)
	local sides
	if minetest.registered_nodes[node.name].buildable_to then
		sides = {sides = {}, connects = {}}
	elseif string.find(node.name, "wires:wire")~=nil then
		sides = dehash_sides(minetest.registered_nodes[node.name].basename)
		sides = rotate_sides(sides, node.param2)
	else
		return
	end
	local side = dir_to_side(dir)
	if in_table(sides.sides, side) then return end
	sides.sides[#sides.sides+1] = side
	calculate_connects(sides, pointed_thing.above)
	local hash = hash_sides(sides)
	local nodename = "wires:wire_off_"..wires.wires[hash]
	local param2 = wires.wire_facedirs[hash]
	swap_node(pointed_thing.above, node, {name = nodename, param2 = param2})
	update_connections(pointed_thing.above)
	old_mesecon_update_autoconnect(pointed_thing.above)
	if finite_stacks then
		itemstack:take_item()
	end
	return itemstack
end

for _, hash in ipairs(wires.to_register) do
	local sides = dehash_sides(hash)
	local nodebox = {}
	local selection_box = {}
	local texture_bumps = {}
	for _, side in ipairs(sides.sides) do
		nodebox[#nodebox+1] = nodeboxes_sides[side]
		local c = 0
		for _, connect in ipairs(sides.connects) do
			if connect[1] == side then c = c + 1 end
		end
		if c >= 3 then
			nodebox[#nodebox+1] = nodeboxes_bumps[side]
			texture_bumps[#texture_bumps+1] = side
		end
		selection_box[#selection_box+1] = selectionboxes_sides[side]
	end
	for _, connect in ipairs(sides.connects) do
		nodebox[#nodebox+1] = nodeboxes_connects[6*connect[1]+connect[2]]
	end
	local base_nodedef = {
		description = "Test",
		paramtype = "light",
		paramtype2 = "facedir",
		inventory_image = "wire_inv.png",
		wield_image = "wire_inv.png",
		drawtype = "nodebox",
		walkable = false,
		drop = "wires:wire_off_1 "..#sides.sides,
		on_place = place_wire,
		node_placement_prediction = "",
		node_box = {
			type = "fixed",
			fixed = nodebox
		},
		selection_box = {
			type = "fixed",
			fixed = selection_box
		},
		basename = hash,
	}
	local vts = {4, 2, 6, 3, 1, 5}
	if #sides.sides == 2 and sides.sides[1]%3 == sides.sides[2]%3 then -- Two part, special
		local states = {"wires:wire_off_"..hash, "wires:wire_off_on_"..hash, "wires:wire_on_off_"..hash, "wires:wire_on_on_"..hash}
		local tiles = {"wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png"}
		for _, side in ipairs(texture_bumps) do
			tiles[vts[side+1]] = "wire_off_ctr.png"
		end
		local nodedef = update_table(base_nodedef, {
			tiles = tiles,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			mesecons = {
				conductor = {
					states = states,
					rules = get_rules2,
				}
			},
		})
		local tiles_on_off = {"wire_on_and_off.png", "wire_on_and_off.png", "wire_on.png", "wire_off.png", "wire_on_and_off.png^[transformR180", "wire_on_and_off.png"}
		for _, side in ipairs(texture_bumps) do
			if vts[side+1] == 3 then
				tiles_on_off[3] = "wire_on_ctr.png"
			elseif vts[side+1] == 4 then
				tiles_on_off[4] = "wire_off_ctr.png"
			end
		end
		local nodedef_on_off = update_table(base_nodedef, {
			tiles = tiles_on_off,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			mesecons = {
				conductor = {
					states = states,
					rules = get_rules2,
				}
			},
		})
		local tiles_off_on = {"wire_on_and_off.png^[transformR180", "wire_on_and_off.png", "wire_off.png", "wire_on.png", "wire_on_and_off.png", "wire_on_and_off.png^[transformR180"}
		for _, side in ipairs(texture_bumps) do
			if vts[side+1] == 3 then
				tiles_off_on[3] = "wire_off_ctr.png"
			elseif vts[side+1] == 4 then
				tiles_off_on[4] = "wire_on_ctr.png"
			end
		end
		local nodedef_off_on = update_table(base_nodedef, {
			tiles = tiles_off_on,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			mesecons = {
				conductor = {
					states = states,
					rules = get_rules2,
				}
			},
		})
		local tiles_on = {"wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png"}
		for _, side in ipairs(texture_bumps) do
			tiles_on[vts[side+1]] = "wire_on_ctr.png"
		end
		local nodedef_on_on = update_table(base_nodedef, {
			tiles = tiles_on,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			mesecons = {
				conductor = {
					states = states,
					rules = get_rules2,
				}
			},
		})
		if hash == 1 then
			nodedef.groups.not_in_creative_inventory = nil
		end
		minetest.register_node("wires:wire_off_"..hash, nodedef)
		minetest.register_node("wires:wire_off_on_"..hash, nodedef_off_on)
		minetest.register_node("wires:wire_on_off_"..hash, nodedef_on_off)
		minetest.register_node("wires:wire_on_on_"..hash, nodedef_on_on)
	else
		local tiles = {"wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png", "wire_off.png"}
		for _, side in ipairs(texture_bumps) do
			tiles[vts[side+1]] = "wire_off_ctr.png"
		end
		local nodedef = update_table(base_nodedef, {
			tiles = tiles,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			on_place = place_wire,
			mesecons = {
				conductor = {
					state = "off",
					onstate = "wires:wire_on_"..hash,
					rules = get_rules,
				}
			},
		})
		local tiles_on = {"wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png", "wire_on.png"}
		for _, side in ipairs(texture_bumps) do
			tiles_on[vts[side+1]] = "wire_on_ctr.png"
		end
		local nodedef_on = update_table(base_nodedef, {
			tiles = tiles_on,
			groups = {dig_immediate = 3, mesecon = 2, not_in_creative_inventory = 1},
			mesecons = {
				conductor = {
					state = "on",
					offstate = "wires:wire_off_"..hash,
					rules = get_rules,
				}
			},
		})
		if hash == 1 then
			nodedef.groups.not_in_creative_inventory = nil
		end
		minetest.register_node("wires:wire_off_"..hash, nodedef)
		minetest.register_node("wires:wire_on_"..hash, nodedef_on)
	end
end

minetest.register_on_placenode(function(pos, node)
	update_connections(pos)
	old_mesecon_update_autoconnect(pos)
end)

minetest.register_on_dignode(function(pos, oldnode, digger)
	if not minetest.registered_nodes[oldnode.name] then return end
	mesecon.on_dignode(pos, oldnode)
	if ATTACHED then
		local nfound = 0
		for side = 0, 5 do
			local npos = vector.add(pos, side_to_dir((side+3)%6))
			local nnode = minetest.get_node(npos)
			if string.find(nnode.name, "wires:wire") ~= nil and minetest.registered_nodes[nnode.name] then
				if string.find(nnode.name, "on") ~= nil then state = "on" end
				local hash = minetest.registered_nodes[nnode.name].basename
				local sides = dehash_sides(hash)
				sides = rotate_sides(sides, nnode.param2)
				local ns = {}
				for _, i in ipairs(sides.sides) do
					if i ~= side then
						ns[#ns+1] = i
					else
						nfound = nfound + 1
					end
				end
				if #ns ~= 0 then
					sides.sides = ns
					calculate_connects(sides, npos)
					local hash = hash_sides(sides)
					nnode.name = "wires:wire_off_"..wires.wires[hash]
					nnode.param2 = wires.wire_facedirs[hash]
				else
					nnode.name = "air"
					nnode.param2 = 0
				end
				minetest.swap_node(npos, nnode)
				mesecon.on_placenode(npos, nnode)
			end
		end
		minetest.handle_node_drops(pos, {ItemStack("wires:wire_off_1 "..nfound)}, digger)
	end
	update_connections(pos)
	old_mesecon_update_autoconnect(pos)
end)

minetest.register_tool("wires:cutter", {
	description = "Wire cutter",
	inventory_image = "cutters.png",
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then return end
		local above = pointed_thing.above
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		if not minetest.registered_nodes[node.name] then return end
		if string.find(node.name, "wires:wire") == nil then
			minetest.registered_nodes[node.name].on_punch(under, node, user)
			return
		end
		local dir = user:get_look_dir()
		local ppos = user:getpos()
		ppos.y = ppos.y + 1.5 -- Camera
		ppos = vector.add(ppos, vector.subtract(above, under))
		local s = dir_to_side(vector.subtract(under, above))
		local s2
		if s%3 == 0 then -- X coordinate
			local xint = (above.x+under.x)/2
			local t = (xint-ppos.x)/dir.x
			local yint = ppos.y+dir.y*t - under.y
			local zint = ppos.z+dir.z*t - under.z
			if math.abs(yint)>math.abs(zint) then
				if yint < 0 then
					s2 = 4
				else
					s2 = 1
				end
			else
				if zint < 0 then
					s2 = 5
				else
					s2 = 2
				end
			end
		elseif s%3 == 1 then -- Y
			local yint = (above.y+under.y)/2
			local t = (yint-ppos.y)/dir.y
			local xint = ppos.x+dir.x*t - under.x
			local zint = ppos.z+dir.z*t - under.z
			if math.abs(xint)>math.abs(zint) then
				if xint < 0 then
					s2 = 3
				else
					s2 = 0
				end
			else
				if zint < 0 then
					s2 = 5
				else
					s2 = 2
				end
			end
		else -- Z
			local zint = (above.z+under.z)/2
			local t = (zint-ppos.z)/dir.z
			local yint = ppos.y+dir.y*t - under.y
			local xint = ppos.x+dir.x*t - under.x
			if math.abs(yint)>math.abs(xint) then
				if yint < 0 then
					s2 = 4
				else
					s2 = 1
				end
			else
				if xint < 0 then
					s2 = 3
				else
					s2 = 0
				end
			end
		end
		local meta = minetest.get_meta(under)
		meta:set_int("noconnect"..s..s2, 1)
		update_connections(under)
	end,
})
