# typed: false
# frozen_string_literal: true

desc "Check if all LSP request visits are marked as override"
task :check_visit_overrides do
  require "objspace"
  require "ruby_lsp/internal"
  Dir["#{Dir.pwd}/lib/ruby_lsp/requests/*.rb"].each { |file| require(file) }

  errors = Hash.new { |h, k| h[k] = [] }

  ObjectSpace
    .each_object(Class)
    .select { |klass| klass < RubyLsp::Requests::BaseRequest }
    .each do |request|
      sigs = T::Private::Methods.instance_variable_get(:@sig_wrappers)
      public_visits = request.instance_methods(false).grep(/^visit.*/)
      private_visits = request.private_instance_methods(false).grep(/^visit.*/)

      (public_visits + private_visits).each do |visit|
        key = T::Private::Methods.send(:method_owner_and_name_to_key, request, visit)
        mode = sigs[key].call.mode
        errors[request] << visit unless mode == "override"
      end
    end

  if errors.any?
    puts <<~ERROR
      The following request visits are not marked as override:

      #{errors.map { |request, visits| "#{request}: #{visits.join(", ")}" }.join("\n")}
    ERROR

    exit!
  end

  puts "All requests are using valid visits"
end
