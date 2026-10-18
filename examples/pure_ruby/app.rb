# frozen_string_literal: true

# The whole producer in one file: a Rack endpoint that turns one RubyLLM chat
# turn into one AG-UI run and writes the events as Server-Sent Events.
#
#   rake example                        # one run, then the run that resumes it
#   rackup examples/pure_ruby/config.ru # serves POST / on port 9292
#
# Without a provider configured it drives ScriptedChat, which plays RubyLLM's
# callback contract offline, so the example runs with no credentials and no
# network. With one, it drives a real RubyLLM::Chat:
#
#   RUBY_LLM_AG_UI_EXAMPLE_MODEL=gpt-4o-mini ruby examples/pure_ruby/app.rb
#
# Load provider credentials through the environment or an untracked env file.
#
# What a real host adds to this: authentication, the scope built from the
# authenticated actor, the chat (and its history) for the thread, a durable run
# store and a re-authorization step before any approved tool runs. The gem is
# the same in both cases.

require 'json'
require 'ruby_llm/ag_ui'

require_relative 'scripted_chat'

module AgUiExample
  # One actor on one thread. A real host derives these from authenticated
  # identity; a client never supplies them.
  SCOPE = 'example:actor-1'
  THREAD_ID = 'thread-1'

  # The run store. In-process is enough for a single-process example; a host
  # that runs more than one worker uses a durable store instead.
  def self.store
    @store ||= RubyLLM::AgUI::Store::MemoryStore.new
  end

  # The stream the gem writes to. Any object with #write is a stream; #flush is
  # optional, so a Rack body does not have to grow one.
  class Sink
    def initialize(&block)
      @block = block
    end

    def write(frame)
      @block.call(frame)
      frame.bytesize
    end

    def flush; end
  end

  # The Rack body: it runs the turn and yields each frame the gem writes, so a
  # server that streams (Puma does) flushes events as they happen instead of
  # buffering the whole run.
  class Frames
    def initialize(&run)
      @run = run
    end

    def each(&block)
      return enum_for(:each) unless block

      @run.call(Sink.new(&block))
    end
  end

  # The host's side of the contract: it parses the input, chooses the chat, and
  # hands both to the gem.
  class App
    def call(env)
      input = RubyLLM::AgUI::Input.parse(env['rack.input'].read)
      [200, RubyLLM::AgUI::SSEWriter.headers, Frames.new { |sink| stream(chat, input, sink) }]
    rescue RubyLLM::AgUI::InputError => e
      # A refused input is refused before any event: the client gets the status
      # the error names, not half a run.
      status = e.http_status
      [status, { 'Content-Type' => 'text/plain; charset=utf-8' }, [e.message]]
    end

    private

    # A real RubyLLM chat when a model is configured, the offline script
    # otherwise. A host builds this per thread and decides which tools and model
    # the actor may use; nothing in the client's input chooses either.
    def chat
      model = ENV['RUBY_LLM_AG_UI_EXAMPLE_MODEL'].to_s
      model.empty? ? ScriptedChat.new : RubyLLM::Chat.new(model: model)
    end

    def stream(chat, input, sink)
      run = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: SCOPE, store: AgUiExample.store)
      run.stream(to: sink)
    end
  end

  # Builds the input a client would POST: one user message, and, on the run that
  # answers an interrupt, the resume entry for it.
  def self.input(run_id, resume: [])
    body = {
      'threadId' => THREAD_ID,
      'runId' => run_id,
      'messages' => [{ 'id' => 'm1', 'role' => 'user', 'content' => 'Cancel order 42.' }]
    }
    body['resume'] = resume.map { |id| { 'interruptId' => id, 'status' => 'resolved' } } if resume.any?
    RubyLLM::AgUI::Input.parse(JSON.generate(body))
  end

  # Streams one run and returns its record.
  def self.stream_run(chat:, input:, &frames)
    run = RubyLLM::AgUI::Run.new(chat: chat, input: input, scope: SCOPE, store: store)
    run.stream(to: Sink.new(&frames))
  end

  # The `rake example` entry point: an interrupted run and the run that answers
  # it, printed as the frames a client would receive.
  def self.demo(io: $stdout)
    chat = ScriptedChat.new
    io.puts 'The tool result below is [redacted] because redaction is on by'
    io.puts 'default; a host opts out with RubyLLM::AgUI::Redaction.method(:none).'
    io.puts '--- run 1: a tool needs a human, so the run ends interrupted ---'
    first = print_run(chat, 'run-1', io)
    interrupt = first.pending_interrupts.first
    io.puts "\n--- run 1 ended #{first.status}: #{interrupt.message} (#{interrupt.id}) ---\n\n"

    io.puts '--- run 2: the client answers that interrupt ---'
    second = print_run(chat, 'run-2', io, resume: [interrupt.id])
    io.puts "\n--- run 2 ended #{second.status} ---"
  end

  # Streams one run to +io+ as the frames arrive and returns its record.
  def self.print_run(chat, run_id, io, resume: [])
    stream_run(chat: chat, input: input(run_id, resume: resume)) { |frame| io.print frame }
  end
end

AgUiExample.demo if __FILE__ == $PROGRAM_NAME
