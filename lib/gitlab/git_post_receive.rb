# frozen_string_literal: true

module Gitlab
  class GitPostReceive
    include Gitlab::Identifier
    attr_reader :project, :identifier, :changes, :push_options

    def initialize(project, identifier, changes, push_options = {})
      @project = project
      @identifier = identifier
      @changes = parse_changes(changes)
      @push_options = push_options
    end

    def identify
      super(identifier)
    end

    def includes_branches?
      changes.includes_branches?
    end

    def includes_tags?
      changes.includes_tags?
    end

    def includes_default_branch?
      # If the branch doesn't have a default branch yet, we presume the
      # first branch pushed will be the default.
      return true unless project.default_branch.present?

      changes.branch_changes.any? do |change|
        Gitlab::Git.branch_name(change[:ref]) == project.default_branch
      end
    end

    private

    def parse_changes(changes)
      deserialized_changes = utf8_encode_changes(changes).each_line

      Git::Changes.new.tap do |collection|
        deserialized_changes.each_with_index do |raw_change, index|
          oldrev, newrev, ref = raw_change.strip.split(' ')
          change = { index: index, oldrev: oldrev, newrev: newrev, ref: ref }

          if Git.branch_ref?(ref)
            collection.add_branch_change(change)
          elsif Git.tag_ref?(ref)
            collection.add_tag_change(change)
          end
        end
      end
    end

    def utf8_encode_changes(changes)
      changes.force_encoding('UTF-8')
      return changes if changes.valid_encoding?

      # Convert non-UTF-8 branch/tag names to UTF-8 so they can be dumped as JSON.
      detection = CharlockHolmes::EncodingDetector.detect(changes)
      return changes unless detection && detection[:encoding]

      CharlockHolmes::Converter.convert(changes, detection[:encoding], 'UTF-8')
    end
  end
end
