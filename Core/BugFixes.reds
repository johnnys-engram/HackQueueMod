@wrapMethod(QuickhacksListGameController)
protected cb func OnMemoryPercentUpdate(value: Float) -> Bool {
    let fillCells: Int32;
    let maxCells: Int32;
    let usedCells: Int32;
    
    if IsDefined(this.m_selectedData) {
      usedCells = this.m_selectedData.m_cost;
    };
    
    maxCells = FloorF(GameInstance.GetStatsSystem(this.m_gameInstance).GetStatValue(Cast<StatsObjectID>(this.GetPlayerControlledObject().GetEntityID()), gamedataStatType.Memory));
    
    // FIX: Use actual current memory value instead of percentage calculation
    fillCells = FloorF(GameInstance.GetStatPoolsSystem(this.m_gameInstance).GetStatPoolValue(Cast<StatsObjectID>(this.GetPlayerControlledObject().GetEntityID()), gamedataStatPoolType.Memory, false));
    
    if !this.GetRootWidget().IsVisible() || this.m_lastFillCells == fillCells && this.m_lastUsedCells == usedCells && this.m_lastMaxCells == maxCells {
      return false;
    };
    
    this.m_lastFillCells = fillCells;
    this.m_lastUsedCells = usedCells;
    this.m_lastMaxCells = maxCells;
    this.UpdateMemoryBar();
    
    return true;
}