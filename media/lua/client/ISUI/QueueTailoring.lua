require "TimedActions/ISInventoryTransferAction"

InventoryTransferByTypeAction = ISInventoryTransferAction:derive("InventoryTransferByTypeAction");

function InventoryTransferByTypeAction:isValid()
  
  local ofType = {}
  for i=1, self.srcContainer:getItems():size() do
    item = self.srcContainer:getItems():get(i-1);
    if item and self.itemType == item:getType() then
      table.insert(ofType, item);
    end
  end
  
  if #ofType > 1 then
    return true;
  end
  
  if not self.destContainer or not self.srcContainer then return false; end
  if (not self.destContainer:isExistYet()) or (not self.srcContainer:isExistYet()) then
    return false
  end

  local parent = self.srcContainer:getParent()
  -- Duplication exploit: drag items from a corpse to another container while pickup up the corpse.
  -- ItemContainer:isExistYet() would detect this if SystemDisabler.doWorldSyncEnable was true.
  if instanceof(parent, "IsoDeadBody") and parent:getStaticMovingObjectIndex() == -1 then
    return false
  end

  if isClient() then
    local limit = getServerOptions():getInteger("ItemNumbersLimitPerContainer")
    if limit > 0 and (not instanceof(self.destContainer:getParent(), "IsoGameCharacter")) and self.destContainer:getItems():size()+1 > limit then
      return false
    end
  end

  if ISTradingUI.instance and ISTradingUI.instance:isVisible() then
    return false;
  end

  if self.srcContainer == self.destContainer then return false; end

   
  return false;
end


function InventoryTransferByTypeAction:start()

  self.item = self.character:getInventory():getItemFromType(self.itemType, true, true);
  
  if self:isAlreadyTransferred(self.item) then
    self.selectedContainer = nil
    self.action:setTime(0)
    return
  end

  if self.character:isPlayerMoving() then
    self.maxTime = self.maxTime * 1.5
    self.action:setTime(self.maxTime)
  end

    -- stop microwave working when putting new stuff in it
  if self.destContainer and self.destContainer:getType() == "microwave" and self.destContainer:getParent() and self.destContainer:getParent():Activated() then
    self.destContainer:getParent():setActivated(false);
  end
  if self.srcContainer and self.srcContainer:getType() == "microwave" and self.srcContainer:getParent() and self.srcContainer:getParent():Activated() then
    self.srcContainer:getParent():setActivated(false);
  end

  if not ISInventoryTransferAction.putSound or not self.character:getEmitter():isPlaying(ISInventoryTransferAction.putSound) then
    -- Players with the Deaf trait don't play sounds.  In multiplayer, we mustn't send multiple sounds to other clients.
    if ISInventoryTransferAction.putSoundTime + ISInventoryTransferAction.putSoundDelay < getTimestamp() then
      ISInventoryTransferAction.putSoundTime = getTimestamp()
      ISInventoryTransferAction.putSound = self.character:getEmitter():playSound("PutItemInBag")
    end
  end

  self:startActionAnim()
end


function InventoryTransferByTypeAction:new(character, itemType, srcContainer, destContainer, time)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.character = character;
  o.itemType = itemType;
  o.srcContainer = srcContainer;
  o.destContainer = destContainer;
  -- handle people right click the same item while eating it
  if not srcContainer or not destContainer then
    o.maxTime = 0;
    return o;
  end
  o.stopOnWalk = not o.destContainer:isInCharacterInventory(o.character) or (not o.srcContainer:isInCharacterInventory(o.character))
  if (o.srcContainer == character:getInventory()) and (o.destContainer:getType() == "floor") then
    o.stopOnWalk = false
  end
  o.stopOnRun = true;
  if destContainer:getType() ~= "TradeUI" and srcContainer:getType() ~= "TradeUI" then
    o.maxTime = 120;
    -- increase time for bigger objects or when backpack is more full.
    local destCapacityDelta = 1.0;

    if o.srcContainer == o.character:getInventory() then
      if o.destContainer:isInCharacterInventory(o.character) then
        destCapacityDelta = o.destContainer:getCapacityWeight() / o.destContainer:getMaxWeight();
      else
        o.maxTime = 50;
      end
    elseif not o.srcContainer:isInCharacterInventory(o.character) then
      if o.destContainer:isInCharacterInventory(o.character) then
        o.maxTime = 50;
      end
    end

    if destCapacityDelta < 0.4 then
      destCapacityDelta = 0.4;
    end

    local item = o.character:getInventory():getItemFromType(o.itemType, true, true);
    local w = item:getActualWeight();
    if w > 3 then w = 3; end;
    o.maxTime = o.maxTime * (w) * destCapacityDelta;

    if getCore():getGameMode()=="LastStand" then
      o.maxTime = o.maxTime * 0.3;
    end

    if o.destContainer:getType()=="floor" then
      if o.srcContainer == o.character:getInventory() then
        o.maxTime = o.maxTime * 0.1;
      elseif o.srcContainer:isInCharacterInventory(o.character) then
    -- Unpack -> drop
      else
        o.maxTime = o.maxTime * 0.2;
      end
    end

    if character:HasTrait("Dextrous") then
      o.maxTime = o.maxTime * 0.5
    end
    if character:HasTrait("AllThumbs") then
      o.maxTime = o.maxTime * 4.0
    end
  else
    o.maxTime = 0;
  end
  if time then
    o.maxTime = time;
  end
  if character:isTimedActionInstant() then
    o.maxTime = 1;
  end
  if o.maxTime == nil then o.maxTime = 300 end


  return o
end


function InventoryTransferByTypeAction:perform()

  -- item = self.character:getInventory():getItemFromType(self.itemType, true, true);
  self:transferItem(self.item);
  self.action:stopTimedActionAnim();
  self.action:setLoopedAction(false);

  -- needed to remove from queue / start next.
  ISBaseTimedAction.perform(self);

end


function ISGarmentUI:doPatch(fabric, thread, needle, part, context, submenu)
  if not self.clothing:getFabricType() then
    return;
  end

  local hole = self.clothing:getVisual():getHole(part) > 0;
  local patch = self.clothing:getPatchType(part);

  local text = nil;

  if hole then
    text = getText("ContextMenu_PatchHole");
  elseif not patch then
    text = getText("ContextMenu_AddPadding");
  else
    error "patch ~= nil"
  end

  if not submenu then -- after the 2nd iteration we have a submenu, we simply add our different fabric to it
    local option = context:addOption(text);
    submenu = context:getNew(context);
    context:addSubMenu(option, submenu);
  end

  local option = submenu:addOption(fabric:getDisplayName(), self.chr, ISInventoryPaneContextMenu.repairClothing, self.clothing, part, fabric:getType(), thread, needle)
  local tooltip = ISInventoryPaneContextMenu.addToolTip();
  if self.clothing:canFullyRestore(self.chr, part, fabric) then
    tooltip.description = getText("IGUI_perks_Tailoring") .. " :" .. self.chr:getPerkLevel(Perks.Tailoring) .. " <LINE> <RGB:0,1,0> " .. getText("Tooltip_FullyRestore");
  else
    tooltip.description = getText("IGUI_perks_Tailoring") .. " :" .. self.chr:getPerkLevel(Perks.Tailoring) .. " <LINE> <RGB:0,1,0> " .. getText("Tooltip_ScratchDefense")  .. " +" .. Clothing.getScratchDefenseFromItem(self.chr, fabric) .. " <LINE> " .. getText("Tooltip_BiteDefense") .. " +" .. Clothing.getBiteDefenseFromItem(self.chr, fabric);
  end
  option.toolTip = tooltip;

  return submenu;
end

-- function ISGarmentUI:doContextMenu(part, x, y)
--
--
--
--   local context = ISContextMenu.get(self.chr:getPlayerNum(), x, y);
--
--   -- you need thread and needle
--   local thread = self.chr:getInventory():getItemFromType("Thread", true, true);
--   local needle = self.chr:getInventory():getItemFromType("Needle", true, true);
--   local fabric1 = self.chr:getInventory():getItemFromType("RippedSheets", true, true);
--   local fabric2 = self.chr:getInventory():getItemFromType("DenimStrips", true, true);
--   local fabric3 = self.chr:getInventory():getItemFromType("LeatherStrips", true, true);
--
--   -- Require a needle to remove a patch.  Maybe scissors or a knife instead?
--   local patch = self.clothing:getPatchType(part)
--   if patch then
--     local option = context:addOption(getText("ContextMenu_RemovePatch"), self.chr, ISInventoryPaneContextMenu.removePatch, self.clothing, part, needle)
--     local tooltip = ISInventoryPaneContextMenu.addToolTip();
--     option.toolTip = tooltip;
--     if needle then
--       tooltip.description = getText("Tooltip_GetPatchBack", ISRemovePatch.chanceToGetPatchBack(self.chr)) .. " <LINE> <RGB:1,0,0> " .. getText("Tooltip_ScratchDefense")  .. " -" .. patch:getScratchDefense() .. " <LINE> " .. getText("Tooltip_BiteDefense") .. " -" .. patch:getBiteDefense();
--     else
--       tooltip.description = getText("ContextMenu_CantRemovePatch");
--       option.notAvailable = true
--     end
--     return context
--   end
--
--   if not thread or not needle or (not fabric1 and not fabric2 and not fabric3) then
--     local patchOption = context:addOption(getText("ContextMenu_Patch"));
--     patchOption.notAvailable = true;
--     local tooltip = ISInventoryPaneContextMenu.addToolTip();
--     tooltip.description = getText("ContextMenu_CantRepair");
--     patchOption.toolTip = tooltip;
--     return context;
--   end
--
--   local submenu = nil;
--   if fabric1 then
--     submenu = self:doPatch(fabric1, thread, needle, part, context, submenu)
--   end
--   if fabric2 then
--     submenu = self:doPatch(fabric2, thread, needle, part, context, submenu)
--   end
--   if fabric3 then
--     submenu = self:doPatch(fabric3, thread, needle, part, context, submenu)
--   end
--
--   return context;
-- end



ISInventoryPaneContextMenu.repairClothing = function(handler, player, clothing, part, fabricType, thread, needle)
  if needle == nil then
    needle = thread
    thread = fabricType
    fabricType = part
    part = clothing
    clothing = player
    player = handler
  end
  fabric = player:getInventory():getItemFromType(fabricType, true, true);
  thread = player:getInventory():getItemFromType(thread:getType(), true, true);


  if fabric == nil or thread == nil then return end
  if luautils.haveToBeTransfered(player, fabric) then
    xferAction = InventoryTransferByTypeAction:new(player, fabricType, fabric:getContainer(), player:getInventory())
    ISTimedActionQueue.add(xferAction)
  end
  if luautils.haveToBeTransfered(player, thread) then
    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, thread, thread:getContainer(), player:getInventory()))
  end
  if luautils.haveToBeTransfered(player, needle) then
    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, needle, needle:getContainer(), player:getInventory()))
  end
  if luautils.haveToBeTransfered(player, clothing) then
    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, clothing, clothing:getContainer(), player:getInventory()))
  end
  action = ISRepairClothing:new(player, clothing, part, fabricType, thread, needle);
  ISTimedActionQueue.add(action);
end


function ISRepairClothing:new(character, clothing, part, fabricType, thread, needle)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.character = character;
  o.clothing = clothing;
  o.part = part;
  o.fabricType = fabricType;
  o.thread = thread;
  o.needle = needle;
  o.stopOnWalk = true;
  o.stopOnRun = true;
  o.maxTime = 150 - (character:getPerkLevel(Perks.Tailoring) * 6);
  if o.character:isTimedActionInstant() then o.maxTime = 1; end
  return o;
end


function ISRepairClothing:isValid()


  local mfabric = self.character:getInventory():getItemFromType(self.fabricType, true, true);
  local mthread = self.character:getInventory():getItemFromType(self.thread:getType(), true, true);
  local mneedle = self.character:getInventory():getItemFromType(self.needle:getType(), true, true);

  local isvalid = self.character:getInventory():contains(self.clothing) and
    mfabric ~= nil and
    mthread ~= nil and
    mneedle ~= nil 

  return isvalid;

end


function ISRepairClothing:start()

  local inv = self.character:getInventory();
  local fabric = inv:getItemFromType(self.fabricType, true, true);
  local fabricIsInMainInventory = fabric:getContainer() == self.character:getInventory();
  
  local mthread = inv:getItemFromType(self.thread:getType(), true, true);
  local mneedle = inv:getItemFromType(self.needle:getType(), true, true);

  if not inv:contains(self.thread) then
    self.thread = mthread
  end
  if not inv:contains(self.needle) then
    self.needle = mneedle
  end

  if self.clothing:getPatchType(self.part) ~= nil then
    self.action:setTime(0)
    return
  end

  if luautils.haveToBeTransfered(self.character, fabric) or
     luautils.haveToBeTransfered(self.character, self.thread) or
     luautils.haveToBeTransfered(self.character, self.needle) then
    ISInventoryPaneContextMenu:repairClothing(self.character, self.clothing, self.part, self.fabricType, self.thread, self.needle);
    self.action:setTime(0)
    return
  end
  self:setActionAnim(CharacterActionAnims.Craft);
end


function ISRepairClothing:perform()

  local fabric = self.character:getInventory():getItemFromType(self.fabricType, true, true);

  if not luautils.haveToBeTransfered(self.character, fabric) and
     not luautils.haveToBeTransfered(self.character, self.thread) and
     not luautils.haveToBeTransfered(self.character, self.needle) then
    
    self.clothing:addPatch(self.character, self.part, fabric);
    self.character:resetModel();
    self.character:getInventory():Remove(fabric);
    self.thread:Use();

    self.character:getXp():AddXP(Perks.Tailoring, ZombRand(1, 3));

    triggerEvent("OnClothingUpdated", self.character)
  end

    -- needed to remove from queue / start next.
  ISBaseTimedAction.perform(self);
end


function ISRemovePatch:start()
  if self.clothing:getPatchType(self.part) == nil then
    self.action:setTime(0)
  else
    self:setActionAnim(CharacterActionAnims.Craft);
  end
end

function ISRemovePatch:isValid()
  return self.character:getInventory():contains(self.clothing) and
         self.character:getInventory():contains(self.needle) -- and
         -- self.clothing:getPatchType(self.part) ~= nil
end


function ISRemovePatch:perform()

  if self.clothing:getPatchType(self.part) ~= nil then
    -- chance to get the patch back
    if ZombRand(100) < ISRemovePatch.chanceToGetPatchBack(self.character) then
      local patch = self.clothing:getPatchType(self.part);
      local fabricType = ClothingPatchFabricType.fromIndex(patch:getFabricType());
      local item = InventoryItemFactory.CreateItem(ClothingRecipesDefinitions["FabricType"][fabricType:getType()].material);
      self.character:getInventory():addItem(item);
      self.character:getXp():AddXP(Perks.Tailoring, 3);
    end
  
    self.character:getXp():AddXP(Perks.Tailoring, 1);
    
    self.clothing:removePatch(self.part);
    self.character:resetModel();
    triggerEvent("OnClothingUpdated", self.character)
  end

    -- needed to remove from queue / start next.
  ISBaseTimedAction.perform(self);
end