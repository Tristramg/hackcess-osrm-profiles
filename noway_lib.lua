require("lib/access")

-- Paramétrage dans le cadre du projet noway
-- On veut activer ou desactiver certains éléments
block_steps = true
block_escalator = true
block_elevator = true
block_no_wheelchair_entrance = true

function is_steps(way)
	local highway = way.tags:Find("highway")
    local conveying = way.tags:Find("conveying")

    -- We do not want to block escalators that are highway=steps and conveying=something
    if highway=="steps" and conveying==nil then
        return true
    else
        return false
    end
    return true
end

function is_escalator(way)
	local highway = way.tags:Find("highway")
    local conveying = way.tags:Find("conveying")

    -- Escalators are just steps that convey
    if highway=="steps" and conveying ~= nil then
        return true
    else
        return false
    end
end

function is_elevator(node_or_way)
    local highway = node_or_way.tags:Find("highway")
    return highway=="elevator"
end

function is_no_wheelchair_entrance(node)
    return false
end

function noway_block_way(way)
    return (block_steps and is_steps(way)) or
           (block_escalator and is_escalator(way)) or
           (block_elevator and is_elevator(way))
end

function noway_block_node(node)
    return (block_elevator and is_elevator(node)) or
           (block_no_wheelchair_entrance and is_no_wheelchair_entrance(node))
end

-- Fin de la configuration spécifique

barrier_whitelist = { [""] = true, ["cycle_barrier"] = true, ["bollard"] = true, ["entrance"] = true, ["cattle_grid"] = true, ["border_control"] = true, ["toll_booth"] = true, ["sally_port"] = true, ["gate"] = true, ["no"] = true, ["turnstile"] = true}
access_tag_whitelist = { ["yes"] = true, ["foot"] = true, ["permissive"] = true, ["designated"] = true, ["virtual"] = true }
access_tag_blacklist = { ["no"] = true, ["private"] = true, ["agricultural"] = true, ["forestery"] = true }
access_tag_restricted = { ["destination"] = true, ["delivery"] = true }
access_tags_hierachy = { "foot", "access" }
service_tag_restricted = { ["parking_aisle"] = true }
ignore_in_grid = { ["ferry"] = true }
restriction_exception_tags = { "foot" }

walking_speed = 5

speeds = {
  ["primary"] = walking_speed,
  ["primary_link"] = walking_speed,
  ["secondary"] = walking_speed,
  ["secondary_link"] = walking_speed,
  ["tertiary"] = walking_speed,
  ["tertiary_link"] = walking_speed,
  ["unclassified"] = walking_speed,
  ["residential"] = walking_speed,
  ["road"] = walking_speed,
  ["living_street"] = walking_speed,
  ["service"] = walking_speed,
  ["track"] = walking_speed,
  ["path"] = walking_speed,
  ["steps"] = walking_speed,
  ["pedestrian"] = walking_speed,
  ["footway"] = walking_speed,
  ["pier"] = walking_speed,
  ["default"] = walking_speed
}

route_speeds = {
	["ferry"] = 5
}

platform_speeds = {
	["platform"] = walking_speed
}

amenity_speeds = {
	["parking"] = walking_speed,
	["parking_entrance"] = walking_speed
}

man_made_speeds = {
	["pier"] = walking_speed
}

surface_speeds = {
	["fine_gravel"] =   walking_speed*0.75,
	["gravel"] =        walking_speed*0.75,
	["pebbelstone"] =   walking_speed*0.75,
	["mud"] =           walking_speed*0.5,
	["sand"] =          walking_speed*0.5
}

traffic_signal_penalty 	= 2
u_turn_penalty 			= 2
use_turn_restrictions   = false

function get_exceptions(vector)
	for i,v in ipairs(restriction_exception_tags) do
		vector:Add(v)
	end
end

function node_function (node)
    if noway_block_node(node) then
        node.bollard = true
        return 1
    end

	local barrier = node.tags:Find ("barrier")
	local access = Access.find_access_tag(node, access_tags_hierachy)
	local traffic_signal = node.tags:Find("highway")

	-- flag node if it carries a traffic light
	if traffic_signal == "traffic_signals" then
		node.traffic_light = true
	end

	-- parse access and barrier tags
	if access and access ~= "" then
		if access_tag_blacklist[access] then
			node.bollard = true
		else
			node.bollard = false
		end
	elseif barrier and barrier ~= "" then
		if barrier_whitelist[barrier] then
			node.bollard = false
		else
			node.bollard = true
		end
	end

	return 1
end

function way_function (way)
    if noway_block_way(way) then
        return 0
    end

 	-- initial routability check, filters out buildings, boundaries, etc
	local highway = way.tags:Find("highway")
	local route = way.tags:Find("route")
	local man_made = way.tags:Find("man_made")
	local railway = way.tags:Find("railway")
	local amenity = way.tags:Find("amenity")
	local public_transport = way.tags:Find("public_transport")
    if (not highway or highway == '') and
		(not route or route == '') and
		(not railway or railway=='') and
		(not amenity or amenity=='') and
		(not man_made or man_made=='') and
    	(not public_transport or public_transport=='')
    	then
    	return 0
    end

    -- don't route on ways that are still under construction
    if highway=='construction' then
        return 0
    end

	-- access
    local access = Access.find_access_tag(way, access_tags_hierachy)
    if access_tag_blacklist[access] then
		return 0
    end

	local name = way.tags:Find("name")
	local ref = way.tags:Find("ref")
	local junction = way.tags:Find("junction")
	local onewayClass = way.tags:Find("oneway:foot")
	local duration	= way.tags:Find("duration")
	local service	= way.tags:Find("service")
	local area = way.tags:Find("area")
	local foot = way.tags:Find("foot")
	local surface = way.tags:Find("surface")

 	-- name
	if "" ~= ref and "" ~= name then
		way.name = name .. ' / ' .. ref
    elseif "" ~= ref then
    	way.name = ref
	elseif "" ~= name then
		way.name = name
	else
		way.name = "{highway:"..highway.."}"	-- if no name exists, use way type
		                                        -- this encoding scheme is excepted to be a temporary solution
	end

    -- roundabouts
	if "roundabout" == junction then
	  way.roundabout = true;
	end

    -- speed
    if route_speeds[route] then
		-- ferries (doesn't cover routes tagged using relations)
		way.direction = Way.bidirectional
		way.ignore_in_grid = true
		if durationIsValid(duration) then
			way.duration = math.max( 1, parseDuration(duration) )
		else
		 	way.speed = route_speeds[route]
		end
	elseif railway and platform_speeds[railway] then
		-- railway platforms (old tagging scheme)
		way.speed = platform_speeds[railway]
	elseif platform_speeds[public_transport] then
		-- public_transport platforms (new tagging platform)
		way.speed = platform_speeds[public_transport]
	elseif amenity and amenity_speeds[amenity] then
		-- parking areas
		way.speed = amenity_speeds[amenity]
	elseif speeds[highway] then
		-- regular ways
      	way.speed = speeds[highway]
	elseif access and access_tag_whitelist[access] then
	    -- unknown way, but valid access tag
		way.speed = walking_speed
    end

	-- oneway
	if onewayClass == "yes" or onewayClass == "1" or onewayClass == "true" then
		way.direction = Way.oneway
	elseif onewayClass == "no" or onewayClass == "0" or onewayClass == "false" then
		way.direction = Way.bidirectional
	elseif onewayClass == "-1" then
		way.direction = Way.opposite
	else
      way.direction = Way.bidirectional
    end

    -- surfaces
    if surface then
        surface_speed = surface_speeds[surface]
        if surface_speed then
            way.speed = math.min(way.speed, surface_speed)
            way.backward_speed  = math.min(way.backward_speed, surface_speed)
        end
    end

  	way.type = 1
    return 1
end
