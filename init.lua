wires = {}
local finite_stacks = (not minetest.setting_get("creative_mode")) or (minetest.get_modpath("unified_inventory") ~= nil)

dofile(minetest.get_modpath("wires").."/wires_tables.lua")

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

local function is_side_in_pos(pos, side)
	local node = minetest.get_node(pos)
	if string.find(node.name, "wires:wire")==nil then return false end
	local hash = minetest.registered_nodes[node.name].basename
	local sides = dehash_sides(hash)
	sides = rotate_sides(sides, node.param2)
	return in_table(sides.sides, side)
end

local function calculate_connects(sides, pos)
	sides.connects = {}
	for _, side in ipairs(sides.sides) do
		for toside = 0, 5 do
		if side%3 ~= toside%3 then
			if in_table(sides.sides, toside) or is_side_in_pos(vector.add(pos, side_to_dir(toside)), side)
					or is_side_in_pos(vector.add(pos, vector.add(side_to_dir(side), side_to_dir(toside))), (toside+3)%6) then
				sides.connects[#sides.connects+1] = {side, toside}
			end
		end
		end
	end
end

local function update_connection(pos)
	local node = minetest.get_node(pos)
	if string.find(node.name, "wires:wire") == nil then return end
	local sides = dehash_sides(minetest.registered_nodes[node.name].basename)
	sides = rotate_sides(sides, node.param2)
	calculate_connects(sides, pos)
	local hash = hash_sides(sides)
	local nodename = "wires:wire_"..wires.wires[hash]
	local param2 = wires.wire_facedirs[hash]
	minetest.set_node(pos, {name = nodename, param2 = param2})
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

for _, hash in ipairs(wires.to_register) do
	local sides = dehash_sides(hash)
	local nodebox = {}
	for _, side in ipairs(sides.sides) do
		nodebox[#nodebox+1] = nodeboxes_sides[side]
	end
	for _, connect in ipairs(sides.connects) do
		nodebox[#nodebox+1] = nodeboxes_connects[6*connect[1]+connect[2]]
	end
	local nodedef = {
		description = "Test",
		paramtype = "light",
		paramtype2 = "facedir",
		drawtype = "nodebox",
		groups = {cracky = 1},
		tiles = {"test"},
		drop = "wires:wire_1 "..#sides.sides,
		node_box = {
			type = "fixed",
			fixed = nodebox
		},
		basename = hash,
		on_place = function(itemstack, placer, pointed_thing)
			if pointed_thing.type ~= "node" then return end
			local dir = vector.subtract(pointed_thing.under, pointed_thing.above)
			local onto = minetest.get_node(pointed_thing.under)
			if onto.name == "air" or string.find(onto.name, "wires:wire") then return end
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
			local nodename = "wires:wire_"..wires.wires[hash]
			local param2 = wires.wire_facedirs[hash]
			minetest.set_node(pointed_thing.above, {name = nodename, param2 = param2})
			update_connections(pointed_thing.above)
			if finite_stacks then
				itemstack:take_item()
			end
			return itemstack
		end,
	}
	if hash ~= 1 then
		nodedef.groups.not_in_creative_inventory = 1
	end
	minetest.register_node("wires:wire_"..hash, nodedef)
end

minetest.register_on_dignode(function(pos, oldnode, digger)
	local nfound = 0
	for side = 0, 5 do
		local npos = vector.add(pos, side_to_dir((side+3)%6))
		local nnode = minetest.get_node(npos)
		if string.find(nnode.name, "wires:wire") ~= nil then
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
				nnode.name = "wires:wire_"..wires.wires[hash]
				nnode.param2 = wires.wire_facedirs[hash]
			else
				nnode.name = "air"
				nnode.param2 = 0
			end
			minetest.set_node(npos, nnode)
		end
	end
	minetest.handle_node_drops(pos, {ItemStack("wires:wire_1 "..nfound)}, digger)
	update_connections(pos)
end)
