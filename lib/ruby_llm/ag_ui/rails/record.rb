# frozen_string_literal: true

require 'active_record'

module RubyLLM
  module AgUI
    module Rails
      # The durable form of one core run record.
      #
      # The core RunRecord stays the authority; this row is where it lives
      # between requests, so a run reserved on one Puma worker is the same run on
      # the next. Identity is duplicated out of the payload into indexed columns
      # so a thread can be listed without parsing JSON, and the payload is
      # written whole because a record is immutable: there is no partial update
      # to make.
      #
      # Create the table with `bin/rails generate ruby_llm:ag_ui:install`.
      class Record < ::ActiveRecord::Base
        self.table_name = 'ruby_llm_ag_ui_runs'

        # The core record this row stores.
        def as_run_record
          ::RubyLLM::AgUI::RunRecord.from_storage(payload)
        end

        # Writes +record+ onto this row and returns the record.
        #
        # The identity columns are not writable: a row keeps the identity it was
        # reserved with, so a record cannot be stored under another run's key.
        def write_run_record(record)
          update!(digest: record.digest, status: record.status.to_s, sequence: record.sequence,
                  payload: record.to_storage)
          record
        end

        # An unsaved row carrying +record+.
        def self.from_run_record(record)
          new(
            scope: record.scope, thread_id: record.thread_id, run_id: record.run_id, digest: record.digest,
            status: record.status.to_s, sequence: record.sequence, payload: record.to_storage
          )
        end
      end
    end
  end
end
