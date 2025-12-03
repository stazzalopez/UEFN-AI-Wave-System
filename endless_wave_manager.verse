using { /Fortnite.com/Game }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Fortnite.com/UI }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /UnrealEngine.com/Temporary/UI }
using { /Verse.org/Colors }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /Verse.org/Assets }
using { SuperPowerShopModule }

EndlessWaveModule := module:

	# Per-room runtime state for Solo zones
	solo_room_state := class:
		var Occupied : logic = false
		var OccupiedBy : ?agent = false
		var Difficulty : string = ""
		# Wave runtime
		var CurrentWave : int = 0
		var KillsRequired : int = 0
		var KillsThisWave : int = 0
		var bIntermissionActive : logic = false
		var bWaveAdvancePending : logic = false
		var IntermissionRemaining : int = 0
		var SpawnedFortCharacters : []fort_character = array{}
		var SpawnedCreatureFortCharacters : []fort_character = array{}

	# Per-room editable device config
	solo_room_config := class<concrete>:
		@editable
		Zone : []mutator_zone_device = array{}
		@editable
		SpawnTeleporter : []teleporter_device = array{}
		@editable
		EasyNpcSpawners : []npc_spawner_device = array{}
		@editable
		EasyCreatureSpawners : []creature_spawner_device = array{}
		@editable
		HardNpcSpawners : []npc_spawner_device = array{}
		@editable
		HardCreatureSpawners : []creature_spawner_device = array{}
		@editable
		WaveTimer : []timer_device = array{}


	# Per-room runtime state for Multi zones
	multi_room_state := class:
		# Number of players currently inside the zone
		var OccupancyCount : int = 0
		# Wave runtime
		var CurrentWave : int = 0
		var KillsRequired : int = 0
		var KillsThisWave : int = 0
		var bIntermissionActive : logic = false
		var bWaveAdvancePending : logic = false
		var IntermissionRemaining : int = 0
		var SpawnedFortCharacters : []fort_character = array{}
		var SpawnedCreatureFortCharacters : []fort_character = array{}

	# Per-room editable device config for Multi zones
	multi_room_config := class<concrete>:
		@editable
		Zone : []mutator_zone_device = array{}
		@editable
		SpawnTeleporter : []teleporter_device = array{}
		@editable
		MultiNpcSpawners : []npc_spawner_device = array{}
		@editable
		MultiCreatureSpawners : []creature_spawner_device = array{}
		@editable
		WaveTimer : []timer_device = array{}


	# Endless Wave manager (menu + solo wave system)
	endless_wave_manager := class(creative_device):

		@editable
		ShopRef : SuperPowerShopModule.superpower_shop_device = SuperPowerShopModule.superpower_shop_device{}

		# Gold settings
		@editable
		GoldPerElimination : type { X:int where X >= 0 } = 75
		@editable
		bUseItemGrantersForGold : logic = false
		# Standalone guard spawners (independent of Solo/Multi zones)
		@editable
		GuardSpawners : []guard_spawner_device = array{}

			# Solo zone configs (rooms)
			@editable
			SoloRoomConfigs : []solo_room_config = array{}
			# Multi zone configs (rooms)
			@editable
			MultiRoomConfigs : []multi_room_config = array{}

		# Input-driven UI
		@editable
		OpenMenuInput : input_trigger_device = input_trigger_device{}
		# Base teleport target (optional)
		@editable
		BaseTeleporter : teleporter_device = teleporter_device{}
		# Campaign teleport target (optional)
		@editable
		CampaignTeleporter : teleporter_device = teleporter_device{}
		# Global reward granters by mode (optional). If empty, RewardGrantersFallback is used
		@editable
		GlobalEasyRewardGranters : []item_granter_device = array{}
		@editable
		GlobalHardRewardGranters : []item_granter_device = array{}
		@editable
		GlobalMultiRewardGranters : []item_granter_device = array{}
		@editable
		RewardGrantersFallback : []item_granter_device = array{}
		var PlayerMenuCanvas : [agent]?canvas = map{}
		# Runtime state
			var SoloStates : []solo_room_state = array{}
			var MultiStates : []multi_room_state = array{}
		var PlayerToRoomIndex : [agent]int = map{}
		var PlayerToMultiRoomIndex : [agent]int = map{}
		var FortCharToRoomIndex : [fort_character]int = map{}
		var FortCharToMultiRoomIndex : [fort_character]int = map{}
		var SelectedDifficulty : [agent]string = map{}
		# Per-player Solo HUD
		var SoloHudByPlayer : [agent]?canvas = map{}
		# Per-player Multi HUD
		var MultiHudByPlayer : [agent]?canvas = map{}
		# Top-center intermission banners
		var SoloBannerByPlayer : [agent]?canvas = map{}
		var MultiBannerByPlayer : [agent]?canvas = map{}
		# Guard: ensure each victim rewards gold only once
		var RewardedSoloVictims : [fort_character]logic = map{}
		var RewardedMultiVictims : [fort_character]logic = map{}

		# ==== Assist tracking (Multi only) ====
		# Per-victim last damage second by agent
		var MultiVictimLastDamageSec : [fort_character][agent]int = map{}
		# Per-victim last damage second by agent for Solo rooms
		var SoloVictimLastDamageSec : [fort_character][agent]int = map{}
		# Per-victim last damage second by agent for standalone Guards
		var GuardVictimLastDamageSec : [fort_character][agent]int = map{}
		# Global seconds counter to timestamp damage events
		var NowSeconds : int = 0
		# Assistant window in seconds (players who damaged within this window get assist)
		@editable
		AssistWindowSeconds : type { X:int where X >= 1 } = 10

			OnBegin<override>()<suspends>:void=
				# Subscribe only the menu input
					OpenMenuInput.PressedEvent.Subscribe(OnOpenMenuPressed)
				# Initialize per-room state and wire zone + spawner events
				for (I := 0 .. SoloRoomConfigs.Length-1):
					set SoloStates += array{ solo_room_state{} }
					if (CfgLocal := SoloRoomConfigs[I]):
						# Subscribe all zones in this room
						for (Z : CfgLocal.Zone):
							Z.AgentEntersEvent.Subscribe(OnAnyZoneEntered)
							Z.AgentExitsEvent.Subscribe(OnAnyZoneExited)
						for (SN : CfgLocal.EasyNpcSpawners):
							SN.SpawnedEvent.Subscribe(OnAnyNpcSpawned)
						for (SC : CfgLocal.EasyCreatureSpawners):
							SC.SpawnedEvent.Subscribe(OnAnyCreatureSpawned)
						for (HN : CfgLocal.HardNpcSpawners):
							HN.SpawnedEvent.Subscribe(OnAnyNpcSpawned)
					for (HC : SoloRoomConfigs[I].HardCreatureSpawners):
						HC.SpawnedEvent.Subscribe(OnAnyCreatureSpawned)
					# Ensure all spawners are disabled on start
					ConfigureRoomSpawners(I, "")
				# Initialize Multi rooms
				for (M := 0 .. MultiRoomConfigs.Length-1):
					set MultiStates += array{ multi_room_state{} }
					if (MCfg := MultiRoomConfigs[M]):
						for (Z2 : MCfg.Zone):
							Z2.AgentEntersEvent.Subscribe(OnAnyMultiZoneEntered)
							Z2.AgentExitsEvent.Subscribe(OnAnyMultiZoneExited)
						for (SN2 : MCfg.MultiNpcSpawners):
							SN2.SpawnedEvent.Subscribe(OnAnyMultiNpcSpawned)
					for (MCreatureSpawner : MultiRoomConfigs[M].MultiCreatureSpawners):
						MCreatureSpawner.SpawnedEvent.Subscribe(OnAnyMultiCreatureSpawned)
					# Ensure all spawners are disabled on start
					ConfigureMultiRoomSpawners(M)
				# Wire standalone guard spawners
				for (GTop : GuardSpawners):
					GTop.SpawnedEvent.Subscribe(OnAnyGuardSpawned)
				# Start 1 Hz tick for assist timestamps
				spawn{ AssistTickLoop() }

		PrintShort(Txt : string):void=
			Print("[Endless] {Txt}")

		TextForUI<localizes>(Text : string) : message = "{Text}"

		# Small on-screen toast showing earned gold like "$200"
		ShowGoldToast(Agent : agent, Amount : int)<suspends>:void=
			if (Player := player[Agent], PlayerUI := GetPlayerUI[Player]):
				var Slots : []canvas_slot = array{}
				set Slots += array
				{
					canvas_slot:
						Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
						Offsets := margin{ Top := -50.0, Left := 150.0, Right := 0.0, Bottom := 0.0 }
						Alignment := vector2{ X := 0.5, Y := 0.5 }
						SizeToContent := true
						Widget := text_block{ DefaultText := TextForUI("${Amount}"), DefaultShadowColor := NamedColors.Black,
						DefaultShadowOpacity := 1.0, DefaultShadowOffset := option{ vector2{ X := 2.0, Y := 2.0 }}, DefaultTextColor := NamedColors.LightGreen, DefaultTextSize := 40.0 }
				}
				Toast : canvas = canvas:
					Slots := Slots
				PlayerUI.AddWidget(Toast, player_ui_slot{ InputMode := ui_input_mode.None })
				Sleep(1.2)
				PlayerUI.RemoveWidget(Toast)

		Fmt2(N : int) : string=
			if (N < 10):
				"0{N}"
			else:
				"{N}"

		FormatMMSS(TotalSeconds : int) : string=
			var Sane : int = if (TotalSeconds > 0) then TotalSeconds else 0
			var MM : int = 0
			# compute minutes via bounded search (0..59)
			for (K := 0 .. 59):
				if (K * 60 <= Sane):
					set MM = K
			SS : int = Sane - (MM * 60)
			"{Fmt2(MM)}:{Fmt2(SS)}"



		# ========== Utilities and Menu ==========

		OnOpenMenuPressed(Agent : agent):void=
			# Toggle menu canvas (background + Easy/Hard/Multi)
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (Tmp := PlayerMenuCanvas[Agent]):
					if (Existing := Tmp?):
						PlayerUI.RemoveWidget(Existing)
						if (set PlayerMenuCanvas[Agent] = false){}
						return
				Menu := CreateMenuCanvas(Agent)
				if (set PlayerMenuCanvas[Agent] = option{ Menu }){}
				PlayerUI.AddWidget(Menu, player_ui_slot{ InputMode := ui_input_mode.All })

		# ======== Selection + Join Solo ========
		HandleDifficultySelection(Agent : agent, Diff : string):void=
			# If player is already in a room, switch difficulty in-place and reset wave
			if (Idx := PlayerToRoomIndex[Agent]):
				RoomIndex := Idx
				if (State := SoloStates[RoomIndex]):
					set State.Difficulty = Diff
					# Persist selection for this agent as well
					if (set SelectedDifficulty[Agent] = Diff){}
					ResetRoomState(RoomIndex)
					# Immediately start Wave 1 with new difficulty
					set State.CurrentWave = 1
					set State.KillsRequired = 7
					set State.KillsThisWave = 0
					ConfigureRoomSpawners(RoomIndex, State.Difficulty)
					UpdateAllHudForRoom(RoomIndex)
					return
			# Otherwise join a room normally
			TryJoinSolo(Agent, Diff)
		TryJoinSolo(Agent : agent, Diff : string):void=
			# Remember choice for possible redirection
			if (set SelectedDifficulty[Agent] = Diff){}
			# Find a free room
			var ChosenRoom : int = -1
			for (I := 0 .. SoloStates.Length-1):
				if (St := SoloStates[I], St.Occupied = false):
					set ChosenRoom = I
			if (ChosenRoom < 0):
				PrintShort("All solo zones are full")
				return
			# Assign difficulty and prepare state
			if (State := SoloStates[ChosenRoom]):
				set State.Difficulty = Diff
				if (State.CurrentWave <= 0):
					set State.CurrentWave = 0
					set State.KillsRequired = 0
					set State.KillsThisWave = 0
			# Teleport player to the chosen room
			if (set PlayerToRoomIndex[Agent] = ChosenRoom){}
			TeleportAgentToRoom(Agent, ChosenRoom)

		CreateMenuCanvas(Agent : agent):canvas=
			var Slots : []canvas_slot = array{}
			# Background image 1048x607 (EndlessBG)
			BGSize := vector2{ X := 1048.0, Y := 607.0 }
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := 0.0, Left := 0.0, Right := 0.0, Bottom := 0.0 }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := true
					Widget := texture_block{ DefaultImage := Textures.EndlessBG, DefaultDesiredSize := BGSize }
			}

			# Close button (top-right of the 1048x607 canvas)
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := -BGSize.Y/2.0 + 61.0, Left := BGSize.X/2.0 - 66.0, Right := 0.0, Bottom := 0.0 }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := true
					Widget := button_quiet{ DefaultText := TextForUI("X") }
			}
			if (BtnClose := button_quiet[Slots[Slots.Length-1].Widget]):
				BtnClose.OnClick().Subscribe(OnMenuClose)

			# Go Base button (top-left inside BG)
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					# smaller button with padding; place relative to BG's top-left
					Offsets := margin{ Top := -BGSize.Y/2.0 + 63.0, Left := -BGSize.X/2.0 + 108.0, Right := 140.0, Bottom := 32.0 }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := false
					Widget := button_quiet{ DefaultText := TextForUI("BASE") }
			}
			if (BtnGoBase := button_quiet[Slots[Slots.Length-1].Widget]):
				BtnGoBase.OnClick().Subscribe(OnMenuGoBase)

			# Buttons
			BtnSize := vector2{ X := 250.0, Y := 48.0 }
			XGap : float = 280.0
			YGap : float = 80.0

			# Solo Easy
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := -YGap + 260.0, Left := -XGap - 50.0, Right := BtnSize.X, Bottom := BtnSize.Y }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := false
					Widget := button_regular{ DefaultText := TextForUI("EASY") }
			}
			if (BtnE := button_regular[Slots[Slots.Length-1].Widget]):
				BtnE.OnClick().Subscribe(OnMenuSoloEasy)

			# Solo Hard
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := -YGap + 320.0, Left := -XGap - 50.0, Right := BtnSize.X, Bottom := BtnSize.Y }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := false
					Widget := button_regular{ DefaultText := TextForUI("HARD X2") }
			}
			if (BtnH := button_regular[Slots[Slots.Length-1].Widget]):
				BtnH.OnClick().Subscribe(OnMenuSoloHard)

			# Multi (disabled)
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := 210.0, Left := 0.0, Right := BtnSize.X, Bottom := BtnSize.Y }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := false
					Widget := button_regular{ DefaultText := TextForUI("MULTI X3") }
			}
			if (BtnM := button_regular[Slots[Slots.Length-1].Widget]):
				BtnM.OnClick().Subscribe(OnMenuMulti)

			# Campaign (same Y as Multi, placed to the right)
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.5 }, Maximum := vector2{ X := 0.5, Y := 0.5 } }
					Offsets := margin{ Top := 210.0, Left := XGap + 50.0, Right := BtnSize.X, Bottom := BtnSize.Y }
					Alignment := vector2{ X := 0.5, Y := 0.5 }
					SizeToContent := false
					Widget := button_regular{ DefaultText := TextForUI("CAMPAIGN") }
			}
			if (BtnC := button_regular[Slots[Slots.Length-1].Widget]):
				BtnC.OnClick().Subscribe(OnMenuCampaign)

			Canvas : canvas = canvas:
				Slots := Slots
			Canvas

		OnMenuSoloEasy(WidgetMessage : widget_message):void=
			HandleDifficultySelection(WidgetMessage.Player, "Easy")
			CloseMenuFor(WidgetMessage.Player)

		OnMenuSoloHard(WidgetMessage : widget_message):void=
			HandleDifficultySelection(WidgetMessage.Player, "Hard")
			CloseMenuFor(WidgetMessage.Player)

		OnMenuMulti(WidgetMessage : widget_message):void=
			TryJoinMulti(WidgetMessage.Player)
			CloseMenuFor(WidgetMessage.Player)

		# ===== Multi: Join/Teleport/UI/HUD =====
		TryJoinMulti(Agent : agent):void=
			# Choose a multi room (prefer least occupied)
			var Chosen : int = 0
			var BestOcc : int = 1000000
			for (I := 0 .. MultiStates.Length-1):
				if (St := MultiStates[I]):
					if (St.OccupancyCount < BestOcc):
						set BestOcc = St.OccupancyCount
						set Chosen = I
			# Teleport and map
			if (set PlayerToMultiRoomIndex[Agent] = Chosen){}
			TeleportAgentToMultiRoom(Agent, Chosen)
			# HUD
			EnsureMultiHud(Agent)
			UpdateMultiHud(Agent, Chosen)

		TeleportAgentToMultiRoom(Agent : agent, RoomIndex : int):void=
			if (FCLocal := Agent.GetFortCharacter[]):
				if (CfgLocal := MultiRoomConfigs[RoomIndex]):
					if (TP := CfgLocal.SpawnTeleporter[0]):
						TX := TP.GetTransform()
						if (FCLocal.TeleportTo[TX.Translation, TX.Rotation]):
							SkipMultiTeleport : logic = false

		CreateMultiHudCanvas():canvas=
			var Slots : []canvas_slot = array{}
			# Top-center single line HUD
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.0 }, Maximum := vector2{ X := 0.5, Y := 0.0 } }
					Offsets := margin{ Top := 100.0, Left := 0.0, Right := 0.0, Bottom := 0.0 }
					Alignment := vector2{ X := 0.5, Y := 0.0 }
					SizeToContent := true
					Widget := text_block{ DefaultText := TextForUI("") , DefaultTextColor := NamedColors.White, DefaultShadowColor := NamedColors.Black, DefaultShadowOpacity := 1.0, DefaultShadowOffset := option{ vector2{ X := 2.0, Y := 2.0 }}, DefaultTextSize := 35.0 }
			}
			Canvas : canvas = canvas:
				Slots := Slots
			Canvas

		EnsureMultiHud(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				# Remove old if exists
				if (Tmp := MultiHudByPlayer[Agent]):
					if (Existing := Tmp?):
						PlayerUI.RemoveWidget(Existing)
				NewHud := CreateMultiHudCanvas()
				if (set MultiHudByPlayer[Agent] = option{ NewHud }){}
				PlayerUI.AddWidget(NewHud, player_ui_slot{ InputMode := ui_input_mode.None })

		UpdateMultiHud(Agent : agent, RoomIndex : int):void=
			if (State := MultiStates[RoomIndex]):
				if (Tmp := MultiHudByPlayer[Agent], HudCanvas := Tmp?):
					if (TB := text_block[HudCanvas.Slots[0].Widget]):
						RoomLabel : int = RoomIndex + 1
						WaveVal : int = if (State.CurrentWave > 0) then State.CurrentWave else 0
						var Line : string = "🌀 Wave {WaveVal} (Multi {RoomLabel})  |  🧟 {State.KillsThisWave}/{State.KillsRequired}"
						if (State.bIntermissionActive = true):
							set Line += "  |  ⏳ Next in {State.IntermissionRemaining}s"
						TB.SetText(TextForUI(Line))

		UpdateAllHudForMultiRoom(RoomIndex : int):void=
			for (A -> I : PlayerToMultiRoomIndex):
				if (I = RoomIndex):
					UpdateMultiHud(A, RoomIndex)

		CreateTopBannerCanvas():canvas=
			var Slots : []canvas_slot = array{}
			# Background placeholder (semi-transparent texture can be swapped later)
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.0 }, Maximum := vector2{ X := 0.5, Y := 0.0 } }
					Offsets := margin{ Top := 150.0, Left := 0.0, Right := 0.0, Bottom := 70.0 }
					Alignment := vector2{ X := 0.5, Y := 0.0 }
					SizeToContent := false
					Widget := texture_block{ DefaultImage := Textures.T_WaveBG, DefaultDesiredSize := vector2{ X := 640.0, Y := 70.0 } }
			}
			# Centered text
			set Slots += array
			{
				canvas_slot:
					Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.0 }, Maximum := vector2{ X := 0.5, Y := 0.0 } }
					Offsets := margin{ Top := 150.0, Left := 0.0, Right := 0.0, Bottom := 0.0 }
					Alignment := vector2{ X := 0.5, Y := 0.0 }
					SizeToContent := true
					Widget := text_block{ DefaultText := TextForUI(""), DefaultTextColor := NamedColors.White, DefaultShadowColor := NamedColors.Black, DefaultShadowOpacity := 1.0, DefaultTextSize := 34.0 }
			}
			Canvas : canvas = canvas:
				Slots := Slots
			Canvas

		EnsureMultiBanner(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (Tmp := MultiBannerByPlayer[Agent]):
					if (Existing := Tmp?):
						PlayerUI.RemoveWidget(Existing)
				NewCanvas := CreateTopBannerCanvas()
				if (set MultiBannerByPlayer[Agent] = option{ NewCanvas }){}
				PlayerUI.AddWidget(NewCanvas, player_ui_slot{ InputMode := ui_input_mode.None })

		UpdateMultiBanner(Agent : agent, RoomIndex : int):void=
			if (State := MultiStates[RoomIndex]):
				NextWave : int = if (State.CurrentWave <= 0) then 1 else (State.CurrentWave + 1)
				if (Tmp := MultiBannerByPlayer[Agent], Banner := Tmp?):
					if (TB := text_block[Banner.Slots[1].Widget]):
						TB.SetText(TextForUI("Wave {NextWave} Coming in {FormatMMSS(State.IntermissionRemaining)}"))

		HideMultiBanner(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (Tmp := MultiBannerByPlayer[Agent]):
					if (Banner := Tmp?):
						PlayerUI.RemoveWidget(Banner)
					if (set MultiBannerByPlayer[Agent] = false){}

		ShowMultiBannerForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToMultiRoomIndex):
				if (I = RoomIndex):
					EnsureMultiBanner(A)
					UpdateMultiBanner(A, RoomIndex)

		UpdateAllMultiBannersForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToMultiRoomIndex):
				if (I = RoomIndex):
					UpdateMultiBanner(A, RoomIndex)

		HideMultiBannerForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToMultiRoomIndex):
				if (I = RoomIndex):
					HideMultiBanner(A)

		# Enable/disable multi spawners; only when occupied
		ConfigureMultiRoomSpawners(RoomIndex : int):void=
			if (Cfg := MultiRoomConfigs[RoomIndex]):
				# Disable all first
				for (SN : Cfg.MultiNpcSpawners):
					SN.Disable()
				for (SC : Cfg.MultiCreatureSpawners):
					SC.Disable()
				if (St := MultiStates[RoomIndex]):
					# Guard: if no players inside or in intermission/pending, keep disabled
					if (St.OccupancyCount <= 0):
						return
					if (St.bIntermissionActive = true or St.bWaveAdvancePending = true):
						return
					# Enable creatures every 3rd wave
					var EnableCreaturesThisWave : logic = false
					W := St.CurrentWave
					if (W > 0):
						var FoundMultiple : logic = false
						for (K := 1 .. W):
							if (K * 3 = W):
								set FoundMultiple = true
						set EnableCreaturesThisWave = FoundMultiple
					for (SN2 : Cfg.MultiNpcSpawners):
						SN2.Enable()
					if (EnableCreaturesThisWave = true):
						for (SC2 : Cfg.MultiCreatureSpawners):
							SC2.Enable()

		# Multi wave countdown and advancement
		StartMultiIntermission(RoomIndex : int)<suspends>:void=
			if (State := MultiStates[RoomIndex]):
				# Set intermission flags first so ConfigureMultiRoomSpawners keeps everything disabled
				set State.bIntermissionActive = true
				set State.bWaveAdvancePending = true
				# Disable spawners and clear only creatures
				ConfigureMultiRoomSpawners(RoomIndex)
				for (CF : State.SpawnedCreatureFortCharacters):
					if (CF.GetHealth() > 0.0):
						Args := damage_args{ Amount := CF.GetHealth() + CF.GetShield() + 9999.0 }
						CF.Damage(Args)
				set State.SpawnedCreatureFortCharacters = array{}
				set State.IntermissionRemaining = 10
				if (Cfg := MultiRoomConfigs[RoomIndex]):
					if (WT := Cfg.WaveTimer[0]):
						WT.Start()
				# Always advance after the countdown window, even if no timer device
				spawn{ WaitForMultiTimerThenAdvance(RoomIndex) }
				# HUD countdown
				ShowMultiBannerForRoom(RoomIndex)
				var RemM : int = 10
				for (Step := 1 .. 10):
					Sleep(1.0)
					set RemM = RemM - 1
					set State.IntermissionRemaining = RemM
					UpdateAllHudForMultiRoom(RoomIndex)
					UpdateAllMultiBannersForRoom(RoomIndex)

		WaitForMultiTimerThenAdvance(RoomIndex : int)<suspends>:void=
			Sleep(10.1)
			if (State := MultiStates[RoomIndex]):
				if (State.bWaveAdvancePending = true):
					AdvanceMultiWave(RoomIndex)

		AdvanceMultiWave(RoomIndex : int):void=
			if (State := MultiStates[RoomIndex]):
				set State.bIntermissionActive = false
				set State.bWaveAdvancePending = false
				HideMultiBannerForRoom(RoomIndex)
				if (State.CurrentWave <= 0):
					set State.CurrentWave = 1
					set State.KillsRequired = 7
				else:
					set State.CurrentWave += 1
					set State.KillsRequired = State.KillsRequired + 10
				set State.KillsThisWave = 0
				ConfigureMultiRoomSpawners(RoomIndex)
				UpdateAllHudForMultiRoom(RoomIndex)

		# ===== Multi: Zone events =====
		OnAnyMultiZoneEntered(Agent : agent):void=
			# Determine multi room via mapping or nearest
			# If the agent was occupying a Solo room, release that occupancy and detach Solo HUD/banner to avoid overlaps
			if (IdxSolo := PlayerToRoomIndex[Agent]):
				SoloIdx := IdxSolo
				if (StSolo := SoloStates[SoloIdx]):
					if (TmpOcc := StSolo.OccupiedBy?):
						if (TmpOcc = Agent):
							set StSolo.Occupied = false
							set StSolo.OccupiedBy = false
							set StSolo.bIntermissionActive = false
							set StSolo.bWaveAdvancePending = false
				# Remove Solo HUD/banner for this player
			if (P0 := player[Agent], PlayerUI0 := GetPlayerUI[P0]):
				if (TmpHud0 := SoloHudByPlayer[Agent]):
					if (Hud0 := TmpHud0?):
						PlayerUI0.RemoveWidget(Hud0)
					if (set SoloHudByPlayer[Agent] = false){}
			HideSoloBanner(Agent)
			# Mark player as not in a Solo room
			if (set PlayerToRoomIndex[Agent] = -1){}
			var RoomIndex : int = -1
			if (Idx := PlayerToMultiRoomIndex[Agent]):
				set RoomIndex = Idx
			if (RoomIndex < 0):
				set RoomIndex = FindNearestMultiRoomIndexToAgent(Agent)
			if (RoomIndex < 0):
				return
			if (State := MultiStates[RoomIndex]):
				# Persist mapping so future HUD updates reach this player
				if (set PlayerToMultiRoomIndex[Agent] = RoomIndex){}
				# Increase occupancy and start/enable if first entrant
				set State.OccupancyCount = State.OccupancyCount + 1
				# Start wave 1 if not started yet
				if (State.CurrentWave <= 0):
					set State.bIntermissionActive = false
					set State.CurrentWave = 1
					set State.KillsRequired = 7
					set State.KillsThisWave = 0
				ConfigureMultiRoomSpawners(RoomIndex)
				# HUD
				EnsureMultiHud(Agent)
				UpdateMultiHud(Agent, RoomIndex)
				# Force-place the entrant at the Multi spawn to avoid stray teleporters pushing to base
				TeleportAgentToMultiRoom(Agent, RoomIndex)

		OnAnyMultiZoneExited(Agent : agent):void=
			if (Idx2 := PlayerToMultiRoomIndex[Agent]):
				RoomIndex := Idx2
				if (State := MultiStates[RoomIndex]):
					set State.OccupancyCount = if (State.OccupancyCount > 0) then (State.OccupancyCount - 1) else 0
					# If empty, disable spawners but keep wave state
					if (State.OccupancyCount = 0):
						ConfigureMultiRoomSpawners(RoomIndex)
				# Clear mapping for this player
				if (set PlayerToMultiRoomIndex[Agent] = -1){}
			# Remove Multi HUD for this player if showing
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (TmpHud := MultiHudByPlayer[Agent]):
					if (Hud := TmpHud?):
						PlayerUI.RemoveWidget(Hud)
					if (set MultiHudByPlayer[Agent] = false){}
			# Remove Multi banner for this player if showing
			HideMultiBanner(Agent)

		# ===== Multi: Spawner events and elimination =====
		OnAnyMultiNpcSpawned(NpcAgent : agent):void=
			if (FC := NpcAgent.GetFortCharacter[]):
				Idx := FindNearestMultiRoomIndexTo(FC)
				if (Idx >= 0):
					if (St := MultiStates[Idx]):
						set St.SpawnedFortCharacters += array{ FC }
						if (set FortCharToMultiRoomIndex[FC] = Idx){}
						FC.EliminatedEvent().Subscribe(OnAnyMultiEliminated)
						FC.DamagedEvent().Subscribe(OnAnyMultiDamaged)

		OnAnyMultiCreatureSpawned(NpcAgent : agent):void=
			if (FC := NpcAgent.GetFortCharacter[]):
				Idx := FindNearestMultiRoomIndexTo(FC)
				if (Idx >= 0):
					if (St := MultiStates[Idx]):
						set St.SpawnedFortCharacters += array{ FC }
						set St.SpawnedCreatureFortCharacters += array{ FC }
						if (set FortCharToMultiRoomIndex[FC] = Idx){}
						FC.EliminatedEvent().Subscribe(OnAnyMultiEliminated)
						FC.DamagedEvent().Subscribe(OnAnyMultiDamaged)

		# Per-second ticker for assist time window and periodic cleanup
		AssistTickLoop()<suspends>:void=
			loop:
				Sleep(1.0)
				set NowSeconds = NowSeconds + 1
				# Optional cleanup: drop stale entries > 2x window to cap memory
				for (Victim -> ByAgent : MultiVictimLastDamageSec):
					var NewInner : [agent]int = map{}
					for (Ag -> TS : ByAgent):
						if ((NowSeconds - TS) <= (AssistWindowSeconds * 2)):
							if (set NewInner[Ag] = TS){}
					if (NewInner.Length > 0):
						if (set MultiVictimLastDamageSec[Victim] = NewInner){}
					else:
						# Remove victim key entirely if empty
						if (set MultiVictimLastDamageSec[Victim] = map{}){}
				# Cleanup for Solo victims too
				for (VictimS -> ByAgentS : SoloVictimLastDamageSec):
					var NewInnerS : [agent]int = map{}
					for (AgS -> TS2 : ByAgentS):
						if ((NowSeconds - TS2) <= (AssistWindowSeconds * 2)):
							if (set NewInnerS[AgS] = TS2){}
					if (NewInnerS.Length > 0):
						if (set SoloVictimLastDamageSec[VictimS] = NewInnerS){}
					else:
						if (set SoloVictimLastDamageSec[VictimS] = map{}){}
				# Cleanup for Guard victims too
				for (VictimG -> ByAgentG : GuardVictimLastDamageSec):
					var NewInnerG : [agent]int = map{}
					for (AgG -> TSG : ByAgentG):
						if ((NowSeconds - TSG) <= (AssistWindowSeconds * 2)):
							if (set NewInnerG[AgG] = TSG){}
					if (NewInnerG.Length > 0):
						if (set GuardVictimLastDamageSec[VictimG] = NewInnerG){}
					else:
						if (set GuardVictimLastDamageSec[VictimG] = map{}){}

		# Record last damage times for Multi victims by instigating agent
		OnAnyMultiDamaged(DamageResult : damage_result):void=
			if (TargetFC := fort_character[DamageResult.Target]):
				# Track only NPCs/creatures that are part of Multi rooms
				if (FortCharToMultiRoomIndex[TargetFC] >= 0):
					if (IA := DamageResult.Instigator?.GetInstigatorAgent[]):
						# Initialize inner map if needed
						var Inner : [agent]int = map{}
						if (Tmp := MultiVictimLastDamageSec[TargetFC]):
							set Inner = Tmp
						# Stamp current second for this instigator
						if (set Inner[IA] = NowSeconds){}
						if (set MultiVictimLastDamageSec[TargetFC] = Inner){}

		OnAnyGuardSpawned(NpcAgent : agent):void=
			if (FC := NpcAgent.GetFortCharacter[]):
				# Track last damagers for guard kills
				FC.DamagedEvent().Subscribe(OnAnyGuardDamaged)
				FC.EliminatedEvent().Subscribe(OnAnyGuardEliminated)

		OnAnyGuardDamaged(DamageResult : damage_result):void=
			if (TargetFC := fort_character[DamageResult.Target]):
				if (IA := DamageResult.Instigator?.GetInstigatorAgent[]):
					var InnerG : [agent]int = map{}
					if (TmpG := GuardVictimLastDamageSec[TargetFC]):
						set InnerG = TmpG
					if (set InnerG[IA] = NowSeconds){}
					if (set GuardVictimLastDamageSec[TargetFC] = InnerG){}

		OnAnyGuardEliminated(Result : elimination_result):void=
			VictimFC : fort_character = Result.EliminatedCharacter
			# Resolve killer by latest timestamp within window; fallback to Result.Instigator's agent
			var KillerAgentResolved : ?agent = false
			var LatestTsG : int = -1000000
			if (ByAgentG := GuardVictimLastDamageSec[VictimFC]):
				for (AgG -> TSG : ByAgentG):
					if ((NowSeconds - TSG) <= AssistWindowSeconds, TSG >= LatestTsG):
						set LatestTsG = TSG
						set KillerAgentResolved = option{ AgG }
			if (Killer := KillerAgentResolved?):
					KillerGoldG : int = ShopRef.ComputeGoldWithAmplifier(Killer, GoldPerElimination)
					ShopRef.AddGoldToPlayer(Killer, KillerGoldG)
					spawn{ ShowGoldToast(Killer, KillerGoldG) }
			# Clear tracking
			if (set GuardVictimLastDamageSec[VictimFC] = map{}){}

		FindNearestMultiRoomIndexTo(FC : fort_character):int=
			var BestI : int = -1
			var BestDist : float = 1e20
			Loc := FC.GetTransform().Translation
			for (I := 0 .. MultiRoomConfigs.Length-1):
				if (Cfg := MultiRoomConfigs[I]):
					if (TP2 := Cfg.SpawnTeleporter[0]):
						TX := TP2.GetTransform()
						Dist := (TX.Translation - Loc).Length()
						if (Dist < BestDist):
							set BestDist = Dist
							set BestI = I
			BestI

		FindNearestMultiRoomIndexToAgent(Agent : agent):int=
			if (FC := Agent.GetFortCharacter[]):
				return FindNearestMultiRoomIndexTo(FC)
			-1

		OnAnyMultiEliminated(Result : elimination_result):void=
			VictimFC : fort_character = Result.EliminatedCharacter
			# Guard against duplicate reward for same victim
			if (RewardedMultiVictims[VictimFC] = true):
				return
			if (set RewardedMultiVictims[VictimFC] = true){}
			var RoomIndex : int = -1
			if (IdxMap := FortCharToMultiRoomIndex[VictimFC]):
				set RoomIndex = IdxMap
			else:
				set RoomIndex = FindNearestMultiRoomIndexTo(VictimFC)
			if (RoomIndex < 0):
				return
			if (State := MultiStates[RoomIndex]):
				# Ignore eliminations during intermission or pending advance
				if (State.bIntermissionActive = true or State.bWaveAdvancePending = true):
					return
				# Resolve killer: prefer most recent damager within the assist window; fallback to any player in room
				var KillerAgentResolved : ?agent = false
				var LatestTs : int = -1000000
				if (ByAgent := MultiVictimLastDamageSec[VictimFC]):
					for (Ag -> TS : ByAgent):
						if ((NowSeconds - TS) <= AssistWindowSeconds, TS >= LatestTs):
							set LatestTs = TS
							set KillerAgentResolved = option{ Ag }
				# Fallback: any player inside this room
				if (not KillerAgentResolved?):
					for (A -> IRoom : PlayerToMultiRoomIndex):
						if (IRoom = RoomIndex):
							set KillerAgentResolved = option{ A }
				if (Killer := KillerAgentResolved?):
					var GrantersToUse : []item_granter_device = array{}
					set GrantersToUse = if (GlobalMultiRewardGranters.Length > 0) then GlobalMultiRewardGranters else RewardGrantersFallback
					if (P := player[Killer]):
						PrintShort("Grant reward to player (Multi)")
						# Optional: device grants (if configured)
						if (bUseItemGrantersForGold = true):
							for (Gr : GrantersToUse):
								Gr.GrantItem(P)
						# Award amplified gold to killer
						KillerGoldLocal : int = ShopRef.ComputeGoldWithAmplifier(Killer, GoldPerElimination)
						ShopRef.AddGoldToPlayer(Killer, KillerGoldLocal)
						spawn{ ShowGoldToast(Killer, KillerGoldLocal) }
						# Assist awards: all other damagers within window get 50% of killer's gold (floored)
						AssistAmount : int = if (Num := Int[(KillerGoldLocal*1.0)/2.0]) then Num else 0
						if (AssistAmount > 0):
							if (ByAgent2 := MultiVictimLastDamageSec[VictimFC]):
								for (AgAssist -> TS2 : ByAgent2):
									if (AgAssist <> Killer, (NowSeconds - TS2) <= AssistWindowSeconds):
										ShopRef.AddGoldToPlayer(AgAssist, AssistAmount)
										spawn{ ShowGoldToast(AgAssist, AssistAmount) }
				# Clear assist tracking and rewarded marker for this victim
				if (set MultiVictimLastDamageSec[VictimFC] = map{}){}
				if (set RewardedMultiVictims[VictimFC] = false){}
				# Remove from tracked arrays
				var NewArr : []fort_character = array{}
				for (J := 0 .. State.SpawnedFortCharacters.Length-1):
					if (FC2 := State.SpawnedFortCharacters[J], FC2 <> VictimFC):
						set NewArr += array{ FC2 }
				set State.SpawnedFortCharacters = NewArr
				var NewArrC : []fort_character = array{}
				for (K := 0 .. State.SpawnedCreatureFortCharacters.Length-1):
					if (FC3 := State.SpawnedCreatureFortCharacters[K], FC3 <> VictimFC):
						set NewArrC += array{ FC3 }
				set State.SpawnedCreatureFortCharacters = NewArrC
				set State.KillsThisWave += 1
				# Safety: ensure KillsRequired is sane
				if (State.KillsRequired <= 0):
					set State.KillsRequired = if (State.CurrentWave <= 1) then 7 else 1
				PrintShort("[Multi] Wave {State.CurrentWave} Kill {State.KillsThisWave}/{State.KillsRequired}")
				if (State.KillsThisWave < State.KillsRequired):
					UpdateAllHudForMultiRoom(RoomIndex)
					return
				# Requirement met; if already in intermission do nothing
				if (State.bIntermissionActive = true):
					return
				# Offer perk choice to all players in this Multi room upon wave completion
				for (A -> IRoom : PlayerToMultiRoomIndex):
					if (IRoom = RoomIndex):
						ShopRef.RequestPerkChoice(A)
				set State.bIntermissionActive = true
				spawn{ StartMultiIntermission(RoomIndex) }
				UpdateAllHudForMultiRoom(RoomIndex)

		OnMenuGoBase(WidgetMessage : widget_message):void=
			TeleportAgentToBase(WidgetMessage.Player)
			CloseMenuFor(WidgetMessage.Player)

		OnMenuClose(WidgetMessage : widget_message):void=
			CloseMenuFor(WidgetMessage.Player)

		OnMenuCampaign(WidgetMessage : widget_message):void=
			TeleportAgentToCampaign(WidgetMessage.Player)
			CloseMenuFor(WidgetMessage.Player)
		CloseMenuFor(Agent : agent):void=
			if (Player := player[Agent]):
				if (PlayerUI := GetPlayerUI[Player]):
					if (Tmp := PlayerMenuCanvas[Agent]):
						if (Existing := Tmp?):
							PlayerUI.RemoveWidget(Existing)
							if (set PlayerMenuCanvas[Agent] = false){}

		# ========== Zone and Wave Flow ==========
		# ===== HUD Helpers =====
		CreateRoomHudCanvas():canvas=
				var Slots : []canvas_slot = array{}
			# Top-center single line HUD (with difficulty)
				set Slots += array
				{
					canvas_slot:
						Anchors := anchors{ Minimum := vector2{ X := 0.5, Y := 0.0 }, Maximum := vector2{ X := 0.5, Y := 0.0 } }
						Offsets := margin{ Top := 100.0, Left := 0.0, Right := 0.0, Bottom := 0.0 }
						Alignment := vector2{ X := 0.5, Y := 0.0 }
						SizeToContent := true
						Widget := text_block{ DefaultText := TextForUI("") , DefaultTextColor := NamedColors.White, DefaultShadowColor := NamedColors.Black, DefaultShadowOpacity := 1.0, DefaultShadowOffset := option{ vector2{ X := 2.0, Y := 2.0 }}, DefaultTextSize := 35.0 }
				}
				Canvas : canvas = canvas:
					Slots := Slots
				Canvas

		EnsureRoomHud(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				# Remove old if exists
				if (Tmp := SoloHudByPlayer[Agent]):
					if (Existing := Tmp?):
						PlayerUI.RemoveWidget(Existing)
				NewHud := CreateRoomHudCanvas()
				if (set SoloHudByPlayer[Agent] = option{ NewHud }){}
				PlayerUI.AddWidget(NewHud, player_ui_slot{ InputMode := ui_input_mode.None })

		UpdateRoomHud(Agent : agent, RoomIndex : int):void=
			if (State := SoloStates[RoomIndex]):
				if (Tmp := SoloHudByPlayer[Agent], HudCanvas := Tmp?):
					if (TB := text_block[HudCanvas.Slots[0].Widget]):
						DiffLabel : string = if (State.Difficulty = "Hard") then "Hard" else "Easy"
						RoomLabel : int = RoomIndex + 1
						WaveVal : int = if (State.CurrentWave > 0) then State.CurrentWave else 0
						var Line : string = "🌀 Wave {WaveVal} ({DiffLabel})  |  🧟 {State.KillsThisWave}/{State.KillsRequired}"
						if (State.bIntermissionActive = true):
							set Line += "  |  🕛 Next in {State.IntermissionRemaining}s"
						TB.SetText(TextForUI(Line))

		UpdateAllHudForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToRoomIndex):
				if (I = RoomIndex):
					UpdateRoomHud(A, RoomIndex)

		EnsureSoloBanner(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (Tmp := SoloBannerByPlayer[Agent]):
					if (Existing := Tmp?):
						PlayerUI.RemoveWidget(Existing)
				NewCanvas := CreateTopBannerCanvas()
				if (set SoloBannerByPlayer[Agent] = option{ NewCanvas }){}
				PlayerUI.AddWidget(NewCanvas, player_ui_slot{ InputMode := ui_input_mode.None })

		UpdateSoloBanner(Agent : agent, RoomIndex : int):void=
			if (State := SoloStates[RoomIndex]):
				NextWave : int = if (State.CurrentWave <= 0) then 1 else (State.CurrentWave + 1)
				if (Tmp := SoloBannerByPlayer[Agent], Banner := Tmp?):
					if (TB := text_block[Banner.Slots[1].Widget]):
						TB.SetText(TextForUI("Wave {NextWave} Coming in {FormatMMSS(State.IntermissionRemaining)}"))

		HideSoloBanner(Agent : agent):void=
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (Tmp := SoloBannerByPlayer[Agent]):
					if (Banner := Tmp?):
						PlayerUI.RemoveWidget(Banner)
					if (set SoloBannerByPlayer[Agent] = false){}

		ShowSoloBannerForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToRoomIndex):
				if (I = RoomIndex):
					EnsureSoloBanner(A)
					UpdateSoloBanner(A, RoomIndex)

		UpdateAllSoloBannersForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToRoomIndex):
				if (I = RoomIndex):
					UpdateSoloBanner(A, RoomIndex)

		HideSoloBannerForRoom(RoomIndex : int):void=
			for (A -> I : PlayerToRoomIndex):
				if (I = RoomIndex):
					HideSoloBanner(A)

		# Wait for timer device to complete (polled via countdown), then advance exactly once
		WaitForTimerThenAdvance(RoomIndex : int)<suspends>:void=
			# Simply wait until countdown loop in StartIntermission completes updating
			Sleep(10.1)
			if (State := SoloStates[RoomIndex]):
				if (State.bWaveAdvancePending = true):
					AdvanceWave(RoomIndex)
		OnAnyZoneEntered(Agent : agent):void=
			# Ignore Solo zone logic if this agent is currently in a Multi room
			if (MIdx := PlayerToMultiRoomIndex[Agent]):
				if (MIdx >= 0):
					return
			# Determine room via player mapping (teleport sets it)
			var RoomIndex : int = -1
			if (Idx := PlayerToRoomIndex[Agent]):
				set RoomIndex = Idx
			# If we don't have mapping, keep best-effort default 0
			if (RoomIndex < 0):
				set RoomIndex = 0
			if (State := SoloStates[RoomIndex]):
				# Occupancy control
				if (State.Occupied = false):
					set State.Occupied = true
					set State.OccupiedBy = option{ Agent }
					# Hard reset any stale wave state before starting
					ResetRoomState(RoomIndex)
					# Start Wave 1 immediately on zone enter using the agent's selected difficulty if present
					set State.bIntermissionActive = false
					var StartDiff : string = State.Difficulty
					if (Sel := SelectedDifficulty[Agent]):
						set StartDiff = Sel
					set State.Difficulty = StartDiff
					set State.CurrentWave = if (State.CurrentWave <= 0) then 1 else State.CurrentWave
					set State.KillsRequired = if (State.CurrentWave = 1) then 7 else State.KillsRequired
					set State.KillsThisWave = 0
					ConfigureRoomSpawners(RoomIndex, State.Difficulty)
					# HUD
					EnsureRoomHud(Agent)
					UpdateRoomHud(Agent, RoomIndex)
				else:
					# Redirect to another free room if available
					var NewRoom : int = -1
					for (J := 0 .. SoloStates.Length-1):
						if (St2 := SoloStates[J], St2.Occupied = false):
							set NewRoom = J
					if (NewRoom >= 0):
						TeleportAgentToRoom(Agent, NewRoom)
						if (set PlayerToRoomIndex[Agent] = NewRoom){}
					else:
						PrintShort("All solo zones are full")

		OnAnyZoneExited(Agent : agent):void=
			# Ignore Solo zone exit if this agent is currently in a Multi room
			if (MIdx2 := PlayerToMultiRoomIndex[Agent]):
				if (MIdx2 >= 0):
					return
			# If occupant leaves, free the room
			if (Idx2 := PlayerToRoomIndex[Agent]):
				RoomIndex := Idx2
				if (State := SoloStates[RoomIndex]):
					if (Tmp := State.OccupiedBy?):
						if (Tmp = Agent):
							set State.Occupied = false
							set State.OccupiedBy = false
							# Reset wave progress for this room when player leaves
							ConfigureRoomSpawners(RoomIndex, "")
							# Eliminate any remaining spawned NPCs/creatures
							for (FCLeft : State.SpawnedFortCharacters):
								if (FCLeft.GetHealth() > 0.0):
									ArgsReset := damage_args{ Amount := FCLeft.GetHealth() + FCLeft.GetShield() + 9999.0 }
									FCLeft.Damage(ArgsReset)
							set State.SpawnedFortCharacters = array{}
							set State.SpawnedCreatureFortCharacters = array{}
							# Clear runtime state so next entrant starts from Wave 1
							set State.bIntermissionActive = false
							set State.bWaveAdvancePending = false
							set State.IntermissionRemaining = 0
							set State.CurrentWave = 0
							set State.KillsRequired = 0
							set State.KillsThisWave = 0
							set State.Difficulty = ""
			# Clear player→room mapping (sentinel -1)
			if (set PlayerToRoomIndex[Agent] = -1){}
			# Remove HUD for this player if showing
			if (P := player[Agent], PlayerUI := GetPlayerUI[P]):
				if (TmpHud := SoloHudByPlayer[Agent]):
					if (Hud := TmpHud?):
						PlayerUI.RemoveWidget(Hud)
					if (set SoloHudByPlayer[Agent] = false){}
			# Remove Solo banner for this player if showing
			HideSoloBanner(Agent)

		TeleportAgentToRoom(Agent : agent, RoomIndex : int):void=
			if (FCLocal := Agent.GetFortCharacter[]):
				if (CfgLocal := SoloRoomConfigs[RoomIndex]):
					if (TP := CfgLocal.SpawnTeleporter[0]):
						TX := TP.GetTransform()
						if (FCLocal.TeleportTo[TX.Translation, TX.Rotation]):
						SkipSoloTeleport : logic = false

		TeleportAgentToBase(Agent : agent):void=
			if (FCLocal := Agent.GetFortCharacter[]):
				X := BaseTeleporter.GetTransform()
				if (FCLocal.TeleportTo[X.Translation, X.Rotation]):
					SkipBaseTeleport : logic = false

		TeleportAgentToCampaign(Agent : agent):void=
			if (FCLocal := Agent.GetFortCharacter[]):
				CX := CampaignTeleporter.GetTransform()
				if (FCLocal.TeleportTo[CX.Translation, CX.Rotation]):
					SkipCampaignTeleport : logic = false

		# Enable/disable spawners based on difficulty and wave number
		ConfigureRoomSpawners(RoomIndex : int, Difficulty : string):void=
			if (Cfg := SoloRoomConfigs[RoomIndex]):
				# Determine if creatures should be enabled this wave (every 3rd wave)
				var EnableCreaturesThisWave : logic = false
				if (St := SoloStates[RoomIndex]):
					W := St.CurrentWave
					if (W > 0):
						# Enable only when W is divisible by 3
						var DivApprox : int = if (Num := Int[(W*1.0)/3.0]) then Num else 0
						set EnableCreaturesThisWave = logic{ (W - (DivApprox*3)) = 0 }
				# Disable all
				for (SN : Cfg.EasyNpcSpawners):
					SN.Disable()
				for (SC : Cfg.EasyCreatureSpawners):
					SC.Disable()
				for (HN : Cfg.HardNpcSpawners):
					HN.Disable()
				for (HC : Cfg.HardCreatureSpawners):
					HC.Disable()
				# Guard: never enable during countdown/intermission or while waiting on timer
				if (St2 := SoloStates[RoomIndex], St2.bIntermissionActive = true):
					return
				if (St3 := SoloStates[RoomIndex], St3.bWaveAdvancePending = true):
					return
				# Enable chosen
				if (Difficulty = "Easy"):
					for (SN2 : Cfg.EasyNpcSpawners):
						SN2.Enable()
					if (EnableCreaturesThisWave = true):
						for (SC2 : Cfg.EasyCreatureSpawners):
							SC2.Enable()
				# Guards: do not manage enable here; they are independent of zones
				else if (Difficulty = "Hard"):
					for (HN2 : Cfg.HardNpcSpawners):
						HN2.Enable()
					if (EnableCreaturesThisWave = true):
						for (HC2 : Cfg.HardCreatureSpawners):
							HC2.Enable()
				# Guards: do not manage enable here; they are independent of zones
				else:
					# Unknown difficulty: keep all disabled
					return

		# Wave countdown between waves only
		StartIntermission(RoomIndex : int)<suspends>:void=
			if (State := SoloStates[RoomIndex]):
				# Disable spawners and eliminate creatures
				ConfigureRoomSpawners(RoomIndex, "")
				for (CF : State.SpawnedCreatureFortCharacters):
					if (CF.GetHealth() > 0.0):
						Args := damage_args{ Amount := CF.GetHealth() + CF.GetShield() + 9999.0 }
						CF.Damage(Args)
				set State.SpawnedCreatureFortCharacters = array{}
				# Start timer device and wait for it instead of manual countdown
				set State.bIntermissionActive = true
				set State.bWaveAdvancePending = true
				set State.IntermissionRemaining = 10
				if (Cfg := SoloRoomConfigs[RoomIndex]):
					if (WT := Cfg.WaveTimer[0]):
						WT.Start()
						spawn{ WaitForTimerThenAdvance(RoomIndex) }
				# Wait 10s then advance
				ShowSoloBannerForRoom(RoomIndex)
				var RemS : int = 10
				for (Step2 := 1 .. 10):
					Sleep(1.0)
					set RemS = RemS - 1
					set State.IntermissionRemaining = RemS
					UpdateAllHudForRoom(RoomIndex)
					UpdateAllSoloBannersForRoom(RoomIndex)

		AdvanceWave(RoomIndex : int):void=
			if (State := SoloStates[RoomIndex]):
				set State.bIntermissionActive = false
				set State.bWaveAdvancePending = false
				HideSoloBannerForRoom(RoomIndex)
				# Advance wave number and requirements
				if (State.CurrentWave <= 0):
					set State.CurrentWave = 1
					set State.KillsRequired = 7
				else:
					set State.CurrentWave += 1
					# Increment strictly by +1 per wave
					set State.KillsRequired = State.KillsRequired + 2
				set State.KillsThisWave = 0
				ConfigureRoomSpawners(RoomIndex, State.Difficulty)
				UpdateAllHudForRoom(RoomIndex)

		# Removed OnTimerCompleted; AdvanceWave handles enabling after timer

		# ======= Robustness helpers =======
		ResetRoomState(RoomIndex : int):void=
			if (State := SoloStates[RoomIndex]):
				ConfigureRoomSpawners(RoomIndex, "")
				# eliminate remaining
				for (FCLeft : State.SpawnedFortCharacters):
					if (FCLeft.GetHealth() > 0.0):
						ArgsReset := damage_args{ Amount := FCLeft.GetHealth() + FCLeft.GetShield() + 9999.0 }
						FCLeft.Damage(ArgsReset)
				set State.SpawnedFortCharacters = array{}
				set State.SpawnedCreatureFortCharacters = array{}
				set State.bIntermissionActive = false
				set State.bWaveAdvancePending = false
				set State.IntermissionRemaining = 0
				set State.CurrentWave = 0
				set State.KillsRequired = 0
				set State.KillsThisWave = 0

		# Spawner events → track spawned characters and subscribe to elimination
		OnAnyNpcSpawned(NpcAgent : agent):void=
			if (FC := NpcAgent.GetFortCharacter[]):
				Idx := FindNearestRoomIndexTo(FC)
				if (Idx >= 0):
					if (St := SoloStates[Idx]):
						set St.SpawnedFortCharacters += array{ FC }
						if (set FortCharToRoomIndex[FC] = Idx){}
						FC.EliminatedEvent().Subscribe(OnAnyEliminated)

		OnAnyCreatureSpawned(NpcAgent : agent):void=
			if (FC := NpcAgent.GetFortCharacter[]):
				Idx := FindNearestRoomIndexTo(FC)
				if (Idx >= 0):
					if (St := SoloStates[Idx]):
						set St.SpawnedFortCharacters += array{ FC }
						set St.SpawnedCreatureFortCharacters += array{ FC }
						if (set FortCharToRoomIndex[FC] = Idx){}
						FC.EliminatedEvent().Subscribe(OnAnyEliminated)

		FindNearestRoomIndexTo(FC : fort_character):int=
			var BestI : int = -1
			var BestDist : float = 1e20
			Loc := FC.GetTransform().Translation
			for (I := 0 .. SoloRoomConfigs.Length-1):
				if (Cfg := SoloRoomConfigs[I]):
					if (TP2 := Cfg.SpawnTeleporter[0]):
						TX := TP2.GetTransform()
						Dist := (TX.Translation - Loc).Length()
						if (Dist < BestDist):
							set BestDist = Dist
							set BestI = I
			BestI



		OnAnyEliminated(Result : elimination_result):void=
			VictimFC : fort_character = Result.EliminatedCharacter
			# Guard against duplicate reward for same victim
			if (RewardedSoloVictims[VictimFC] = true):
				return
			if (set RewardedSoloVictims[VictimFC] = true){}
			var RoomIndex : int = -1
			# Prefer exact room mapping from spawn time; fallback to nearest
			if (IdxMap := FortCharToRoomIndex[VictimFC]):
				set RoomIndex = IdxMap
			else:
				set RoomIndex = FindNearestRoomIndexTo(VictimFC)
			if (RoomIndex < 0):
				return
			if (State := SoloStates[RoomIndex]):
				# Ignore eliminations during intermission or pending wave advance
				if (State.bIntermissionActive = true or State.bWaveAdvancePending = true):
					return
				# Resolve killer: prefer most recent damager within the assist window; fallback to any player in room
				var KillerAgentResolved : ?agent = false
				var LatestTsSolo : int = -1000000
				if (BySolo := SoloVictimLastDamageSec[VictimFC]):
					for (AgSolo -> TSSolo : BySolo):
						if ((NowSeconds - TSSolo) <= AssistWindowSeconds, TSSolo >= LatestTsSolo):
							set LatestTsSolo = TSSolo
							set KillerAgentResolved = option{ AgSolo }
				# Fallback: any player inside this room
				if (not KillerAgentResolved?):
					for (A -> IRoom : PlayerToRoomIndex):
						if (IRoom = RoomIndex):
							set KillerAgentResolved = option{ A }
				if (Killer := KillerAgentResolved?):
					# Choose global mode-specific granters; fallback if all empty
					var GrantersToUse : []item_granter_device = array{}
					if (State.Difficulty = "Easy"):
						set GrantersToUse = if (GlobalEasyRewardGranters.Length > 0) then GlobalEasyRewardGranters else RewardGrantersFallback
					else if (State.Difficulty = "Hard"):
						set GrantersToUse = if (GlobalHardRewardGranters.Length > 0) then GlobalHardRewardGranters else RewardGrantersFallback
					else:
						set GrantersToUse = if (GlobalMultiRewardGranters.Length > 0) then GlobalMultiRewardGranters else RewardGrantersFallback
					if (P := player[Killer]):
						# Optional device rewards (if these contain gold tokens and you want to keep them)
						if (bUseItemGrantersForGold = true):
							for (Gr2 : GrantersToUse):
								Gr2.GrantItem(P)
						# Amplified gold via shop replaces/augments granters
						AmplifiedGold : int = ShopRef.ComputeGoldWithAmplifier(Killer, GoldPerElimination)
						ShopRef.AddGoldToPlayer(Killer, AmplifiedGold)
						spawn{ ShowGoldToast(Killer, AmplifiedGold) }
				# Clear assist tracking and rewarded marker for this victim
				if (set SoloVictimLastDamageSec[VictimFC] = map{}){}
				if (set RewardedSoloVictims[VictimFC] = false){}
				# Remove from tracked arrays
				var NewArr : []fort_character = array{}
				for (J := 0 .. State.SpawnedFortCharacters.Length-1):
					if (FC2 := State.SpawnedFortCharacters[J], FC2 <> VictimFC):
						set NewArr += array{ FC2 }
				set State.SpawnedFortCharacters = NewArr
				var NewArrC : []fort_character = array{}
				for (K := 0 .. State.SpawnedCreatureFortCharacters.Length-1):
					if (FC3 := State.SpawnedCreatureFortCharacters[K], FC3 <> VictimFC):
						set NewArrC += array{ FC3 }
				set State.SpawnedCreatureFortCharacters = NewArrC
							set State.KillsThisWave += 1
				# Safety: ensure KillsRequired is sane (never 0)
				if (State.KillsRequired <= 0):
					set State.KillsRequired = if (State.CurrentWave <= 1) then 7 else 1
				# Debug: show kill progress
				PrintShort("Wave {State.CurrentWave} Kill {State.KillsThisWave}/{State.KillsRequired}")
				# If requirement not met yet, just update HUD and exit
				if (State.KillsThisWave < State.KillsRequired):
					UpdateAllHudForRoom(RoomIndex)
					return
				# Requirement met; if already in intermission do nothing
				if (State.bIntermissionActive = true):
					return
				# Offer perk choice to all players in this Solo room upon wave completion
				for (A -> IRoom : PlayerToRoomIndex):
					if (IRoom = RoomIndex):
						ShopRef.RequestPerkChoice(A)
				# Start intermission safely once
				set State.bIntermissionActive = true
				spawn{ StartIntermission(RoomIndex) }
				UpdateAllHudForRoom(RoomIndex)


