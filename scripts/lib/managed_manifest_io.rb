#!/usr/bin/env ruby
# Publish a fully materialized manifest, retrying interrupted and short writes.
module WPPluginBaseManagedManifestIO
  def self.write_all(output, content)
    offset = 0
    while offset < content.bytesize
      begin
        written = output.syswrite(content.byteslice(offset, content.bytesize - offset))
      rescue Errno::EINTR
        retry
      end
      raise IOError, 'Managed manifest write made no progress' unless written.positive?

      offset += written
    end
  end

  def self.publish(path, output, unique: false)
    content = File.binread(path)
    content = content.lines.uniq.join if unique
    write_all(output, content)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    STDOUT.binmode
    WPPluginBaseManagedManifestIO.publish(ARGV.fetch(0), STDOUT, unique: ARGV[1] == '--unique')
  rescue StandardError => error
    warn "Cannot publish the managed file manifest: #{error.message}"
    exit 1
  end
end
