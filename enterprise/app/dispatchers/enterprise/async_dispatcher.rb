module Enterprise::AsyncDispatcher
  def listeners
    super + [
      CaptainListener.instance,
      Captain::ReportingEventListener.instance,
      OperationalEngineListener.instance
    ]
  end
end
