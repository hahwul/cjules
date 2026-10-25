require "yaml"

# Every file that carries the release version: how to read it and how to rewrite it.
record Target, label : String, path : String,
  read : Proc(String, String?), write : Proc(String, String, String)

TARGETS = [
  Target.new("Shard", "shard.yml",
    ->(c : String) : String? { YAML.parse(c)["version"].as_s },
    ->(c : String, v : String) { c.gsub(/^(version:\s*)[\d.]+/m, "\\1#{v}") }),
  Target.new("Cjules", "src/cjules/version.cr",
    ->(c : String) : String? { c.match(/VERSION\s*=\s*"([^"]+)"/).try(&.[1]) },
    ->(c : String, v : String) { c.gsub(/VERSION\s*=\s*"[^"]+"/, "VERSION = \"#{v}\"") }),
  Target.new("Snapcraft", "snap/snapcraft.yaml",
    ->(c : String) : String? { YAML.parse(c)["version"].as_s },
    ->(c : String, v : String) { c.gsub(/^(version:\s*)['"]?[\d.]+['"]?/m, "\\1#{v}") }),
  Target.new("PKGBUILD", "aur/PKGBUILD",
    ->(c : String) : String? { c.match(/^pkgver=([\d.]+)/m).try(&.[1]) },
    ->(c : String, v : String) { c.gsub(/^pkgver=[\d.]+/m, "pkgver=#{v}").gsub(/^pkgrel=\d+/m, "pkgrel=1") }),
]

def read_version(t : Target) : String?
  t.read.call(File.read(t.path))
rescue
  nil
end

found = TARGETS.map { |t| {t, read_version(t)} }
unique_versions = found.compact_map(&.[1]).uniq!

# `--check`: report versions and exit non-zero unless they all match.
if ARGV.includes?("--check")
  found.each { |t, v| puts "#{"#{t.label} version:".ljust(18)} #{v || "Not found"}" }
  if unique_versions.empty?
    puts "No versions found!"
    exit 1
  end
  if unique_versions.size == 1
    puts "All versions match: #{unique_versions.first}"
  else
    puts "Versions do not match!"
    puts "Unique versions found: #{unique_versions.join(", ")}"
    exit 1
  end
  exit 0
end

puts "=" * 50
puts "Cjules Version Update Tool"
puts "=" * 50
puts

puts "Current versions:"
found.each { |t, v| puts "  #{t.path.ljust(25)} #{v || "Not found"}" }
puts

if unique_versions.size > 1
  puts "Warning: Versions do not match!"
  puts "  Unique versions found: #{unique_versions.join(", ")}"
  puts
end

# PKGBUILD is deliberately not consulted for the current version.
current_version = found.compact_map { |t, v| v unless t.label == "PKGBUILD" }.first? || "unknown"
puts "Current version: #{current_version}"
puts

print "Enter new version (or press Enter to cancel): "
new_version = gets.try(&.strip) || ""

if new_version.empty?
  puts "Cancelled."
  exit 0
end

unless new_version.matches?(/^\d+\.\d+\.\d+$/)
  puts "Invalid version format. Please use semantic versioning (e.g., 1.2.3)"
  exit 1
end

if new_version == current_version
  puts "New version is the same as current version. No changes made."
  exit 0
end

puts
puts "Updating to version #{new_version}..."
puts

success_count = 0
total_count = 0

found.each do |t, v|
  next unless v
  total_count += 1
  print "  Updating #{t.path}... "
  begin
    File.write(t.path, t.write.call(File.read(t.path), new_version))
    puts "ok"
    success_count += 1
  rescue ex
    puts "  Error updating #{t.path}: #{ex.message}"
    puts "fail"
  end
end

puts
if success_count == total_count
  puts "All #{success_count} files updated successfully to version #{new_version}"
else
  puts "Updated #{success_count}/#{total_count} files"
  exit 1
end
