game.Players.PlayerAdded:Connect(function(player)
	print("Username:", player.Name)
	print("UserId:", player.UserId)
end)