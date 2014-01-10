require_relative 'worker'

module Ntswf
  # Interface for a worker arbitrating tasks, optionally for multiple apps
  module DecisionWorker
    include Ntswf::Worker

    # Process a decision task.
    # The following task values are interpreted:
    # input:: see {Ntswf::Client#start_execution}
    # reason:: reschedule if {RETRY}
    # result:: Interpreted as {Hash}, see below for keys
    # Result keys
    # :seconds_until_retry:: Planned reschedule after task completion
    def process_decision_task
      announce("polling for decision task #{decision_task_list}")
      domain.decision_tasks.poll_for_single_task(decision_task_list) do |task|
        announce("got decision task #{task.workflow_execution.inspect}")
        begin
          task.new_events.each do |event|
            log("processing event #{event.inspect}")
            case event.event_type
            when 'WorkflowExecutionStarted'
              schedule(task, event)
            when 'TimerFired'
              start_event = task.events.first
              keys = [
                :child_policy,
                :execution_start_to_close_timeout,
                :input,
                :tag_list,
                :task_list,
                :task_start_to_close_timeout,
              ]
              attributes = start_event.attributes.to_h.keep_if {|k| keys.include? k}
              task.continue_as_new_workflow_execution(attributes)
            when 'ActivityTaskCompleted'
              result = parse_result(event.attributes.result)
              start_timer(task, result[:seconds_until_retry]) or task.complete_workflow_execution(
                  result: event.attributes.result)
            when 'ActivityTaskFailed'
              if (event.attributes.reason == RETRY)
                schedule(task, task.events.first)
              else
                start_timer(task) or task.fail_workflow_execution(
                    event.attributes.to_h.slice(:details, :reason))
              end
            when 'ActivityTaskTimedOut'
              notify("Timeout in Simple Workflow. Possible cause: all workers busy",
                  workflow_execution: task.workflow_execution.inspect)
              start_timer(task) or task.cancel_workflow_execution(
                  details: 'activity task timeout')
            end
          end
        rescue => e
          notify(e, workflow_execution: task.workflow_execution.inspect)
          raise e
        end
      end
    end

    protected

    def start_timer(task, interval = nil)
      unless interval
        options = parse_input(task.events.first.attributes.input)
        interval = options['interval']
      end
      task.start_timer(interval.to_i) if interval
      interval
    end

    def schedule(task, data_providing_event)
      input = data_providing_event.attributes.input
      options = parse_input(input)
      app_in_charge = options['unit'] || guess_app_from(data_providing_event)
      task_list = activity_task_lists[app_in_charge]
      raise "Missing activity task list config for #{app_in_charge.inspect}" unless task_list

      task.schedule_activity_task(activity_type, {
        heartbeat_timeout: :none,
        input: input,
        task_list: task_list,
        schedule_to_close_timeout: 12 * 3600,
        schedule_to_start_timeout: 10 * 60,
        start_to_close_timeout: 12 * 3600,
      })
    end

    def parse_result(result)
      if result
        value = JSON.parse(result) rescue nil # expecting JSON::ParserError
      end
      value = {} unless value.kind_of? Hash
      value.with_indifferent_access
    end

    private

    # transitional, until all apps speak the input options protocol
    def guess_app_from(data_providing_event)
      data_providing_event.workflow_execution.workflow_type.name[/\w+/]
    end
  end
end