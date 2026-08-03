class Sales::Leads::TimelineBuilderService
  DEFAULT_PER_PAGE = 25

  def initialize(lead:, before: nil, per_page: DEFAULT_PER_PAGE)
    @lead = lead
    @before = before
    @per_page = per_page
  end

  def perform
    entries = (message_entries + note_entries + stage_transition_entries + activity_entries)
              .sort_by { |entry| entry[:created_at] }
              .reverse
              .first(@per_page)

    { entries: entries, next_before: entries.last&.dig(:created_at) }
  end

  private

  def message_entries
    scope = Message.where(conversation_id: @lead.conversations.select(:id)).non_activity_messages
    limited(scope).map { |message| message_entry(message) }
  end

  def note_entries
    limited(@lead.contact.notes.latest).map { |note| note_entry(note) }
  end

  def stage_transition_entries
    limited(@lead.stage_transitions).map { |transition| stage_transition_entry(transition) }
  end

  def activity_entries
    limited(@lead.activities).map { |activity| activity_entry(activity) }
  end

  def limited(scope)
    scope = scope.where('created_at < ?', @before) if @before.present?
    scope.limit(@per_page)
  end

  def message_entry(message)
    {
      type: 'message',
      id: message.id,
      created_at: message.created_at,
      message_type: message.message_type,
      private: message.private,
      content: message.content,
      sender_name: message.sender.try(:name),
      conversation_id: message.conversation_id,
      conversation_display_id: message.conversation.display_id
    }
  end

  def note_entry(note)
    {
      type: 'note',
      id: note.id,
      created_at: note.created_at,
      content: note.content,
      user_name: note.user&.name
    }
  end

  def stage_transition_entry(transition)
    {
      type: 'stage_transition',
      id: transition.id,
      created_at: transition.created_at,
      from_stage_name: transition.from_stage&.name,
      to_stage_name: transition.to_stage.name,
      user_name: transition.user&.name
    }
  end

  def activity_entry(activity)
    {
      type: 'activity',
      id: activity.id,
      created_at: activity.created_at,
      activity_type: activity.activity_type,
      body: activity.body,
      user_name: activity.user&.name
    }
  end
end
