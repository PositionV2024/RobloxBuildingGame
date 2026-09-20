-- ParkourCreatorBrowserRules V1
-- NEW ModuleScript: ServerScriptService > ParkourCreatorBrowserRules
-- Pure request-state rules; no GUI, permissions, DataStores, or side effects.
local Rules = {}
Rules.Config = {
	RequestSeconds = 30,
	ApprovalSeconds = 20,
	TransferSeconds = 45,
	RequestCooldown = 20,
	RecordTTL = 120,
	DirectoryTTL = 45,
	DirectoryFreshSeconds = 30,
	DirectoryRefreshSeconds = 10,
	InboxRefreshSeconds = 3,
	ResultRefreshSeconds = 2,
	PageSize = 100,
	InboxSize = 50,
}

function Rules.Finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Rules.Integer(n)
	return Rules.Finite(n) and n % 1 == 0
end

function Rules.Token(s)
	return type(s) == "string" and #s == 36
		and s:match("^[%x]+%-%x+%-%x+%-%x+%-%x+$") ~= nil
end

function Rules.Active(r, now)
	if type(r) ~= "table" then return false end
	if r.state == "Pending" then return Rules.Finite(r.expiresAt) and r.expiresAt > now end
	if r.state == "Approved" then return Rules.Finite(r.approvedUntil) and r.approvedUntil > now end
	if r.state == "Transferring" then return Rules.Finite(r.transferUntil) and r.transferUntil > now end
	return false
end

function Rules.Terminal(state)
	return state == "Declined" or state == "Expired" or state == "Cancelled"
		or state == "OwnerLeft" or state == "Full" or state == "Failed"
		or state == "Closed" or state == "Arrived"
end

-- Returning nil CANCELS a MemoryStore UpdateAsync. In particular, old timers
-- and replies can never modify a newer request under the same player's key.
function Rules.Transition(old, expectedId, event, now)
	if type(old) ~= "table" or old.id ~= expectedId or Rules.Terminal(old.state) then return nil end
	local state = old.state
	local active = Rules.Active(old, now)
	if event == "Approve" or event == "Decline" then
		if state ~= "Pending" or not active then return nil end
	elseif event == "BeginTransfer" then
		if state ~= "Approved" or not active then return nil end
	elseif event == "Arrive" then
		if state ~= "Transferring" or not active then return nil end
	elseif event == "Expire" then
		if active then return nil end
	elseif event == "Cancel" then
		if state ~= "Pending" and state ~= "Approved" then return nil end
	elseif event == "OwnerLeft" or event == "Full" or event == "Closed" then
		if state ~= "Pending" and state ~= "Approved" then return nil end
	elseif event ~= "Fail" then
		return nil
	end
	local r = table.clone(old)
	local mapped = {Approve="Approved", Decline="Declined", BeginTransfer="Transferring",
		Arrive="Arrived", Expire="Expired", Cancel="Cancelled", Fail="Failed"}
	r.state = mapped[event] or event
	r.revision = (tonumber(old.revision) or 0) + 1
	r.updatedAt = now
	if event == "Approve" then r.approvedUntil = now + Rules.Config.ApprovalSeconds end
	if event == "BeginTransfer" then r.transferUntil = now + Rules.Config.TransferSeconds end
	return r
end

function Rules.ValidListing(d, now, placeId)
	return type(d) == "table" and Rules.Token(d.sessionId)
		and Rules.Integer(d.ownerUserId) and type(d.username) == "string"
		and type(d.displayName) == "string" and d.placeId == placeId
		and Rules.Integer(d.count) and d.count >= 1
		and Rules.Integer(d.limit) and d.limit >= 1 and d.limit <= 5
		and Rules.Finite(d.updatedAt) and now - d.updatedAt <= Rules.Config.DirectoryFreshSeconds
		and now >= d.updatedAt - 10 and d.open == true
end

-- This is the ONLY directory payload sent to a client. Never add accessCode.
function Rules.PublicListing(d)
	return {
		sessionId=d.sessionId, ownerUserId=d.ownerUserId,
		username=d.username, displayName=d.displayName,
		count=d.count, limit=d.limit,
		ready=d.ready == true, accepting=d.accepting == true,
		updatedAt=d.updatedAt,
	}
end

Rules.Messages = {
	Pending="Request sent. Waiting for the Creator's approval.",
	Approved="The Creator approved your request. Preparing to join...",
	Transferring="Joining the Creator server as a Viewer...",
	Declined="The Creator declined your request.",
	Expired="The join request timed out. You can try again.",
	Cancelled="Join request cancelled.",
	OwnerLeft="The Creator left or this session is no longer available.",
	Full="That Creator server is full. No existing guest was removed.",
	Closed="The Creator has paused join requests.",
	Failed="Could not join the Creator server. Please try again.",
	Arrived="You joined as a Viewer. Building needs separate Collaborator permission.",
}
return Rules
