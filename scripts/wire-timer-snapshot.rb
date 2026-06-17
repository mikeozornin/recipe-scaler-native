#!/usr/bin/env ruby
# Creates the HomeWidgetExtension target and wires Phase 1 (TimerSnapshot) files.
# Idempotent: safe to run multiple times.

require 'xcodeproj'

PROJECT_PATH = 'RecipeScalerNative.xcodeproj'
ENTITLEMENTS_SRC = 'HomeWidgetExtension/HomeWidgetExtension.entitlements'
COPY_ENTITLEMENTS_PHASE = 'Copy Widget Entitlements'

project = Xcodeproj::Project.open(PROJECT_PATH)

# Locate targets
core_target = project.targets.find { |t| t.name == 'RecipeScalerCore' }
app_target  = project.targets.find { |t| t.name == 'RecipeScalerNative' }
abort 'RecipeScalerCore target not found' unless core_target
abort 'RecipeScalerNative target not found' unless app_target

def add_swift_file(group, target, rel_path, file_name)
  existing = group.files.find { |f| f.path == rel_path }
  ref = existing || group.new_file(rel_path)
  unless target.source_build_phase.files_references.include?(ref)
    target.add_file_references([ref])
    puts "  [add] #{file_name} -> #{target.name} Sources"
  else
    puts "  [skip] #{file_name} already in #{target.name} Sources"
  end
  ref
end

def ensure_group_file(group, filename, last_known_file_type)
  existing = group.files.find { |f| f.path == filename }
  return existing if existing

  ref = group.new_file(filename)
  ref.last_known_file_type = last_known_file_type
  puts "  [add] #{filename} -> #{group.name} group"
  ref
end

def add_resource_ref(target, file_ref, label)
  return unless file_ref
  if target.resources_build_phase.files_references.include?(file_ref)
    puts "  [skip] #{label} already in #{target.name} Resources"
  else
    target.resources_build_phase.add_file_reference(file_ref)
    puts "  [add] #{label} -> #{target.name} Resources"
  end
end

def remove_entitlements_copy_phase(target)
  target.shell_script_build_phases
    .select { |p| p.name == COPY_ENTITLEMENTS_PHASE }
    .each(&:remove_from_project)
end

def cleanup_widget_build_phases(target, core_product)
  target.source_build_phase.files.to_a.each do |bf|
    ref = bf.file_ref
    next unless ref
    path = ref.path.to_s
    if ref == core_product || path.end_with?('.xcstrings', '.otf')
      bf.remove_from_project
      puts "  [fix] removed #{path} from #{target.name} Sources"
    end
  end
end

def apply_widget_build_settings(target)
  target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = ENTITLEMENTS_SRC
    # Xcode may merge team/base entitlements while packaging; allow that for this
    # extension only (avoids "modified during the build" without a script cycle).
    config.build_settings['CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION'] = 'YES'
    config.build_settings.delete('ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME')
    config.build_settings.delete('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME')
  end
  puts "  [ok] CODE_SIGN_ENTITLEMENTS -> #{ENTITLEMENTS_SRC}"
end

# --- Create HomeWidgetExtension target (idempotent) ---
widget_target = project.targets.find { |t| t.name == 'HomeWidgetExtension' }
unless widget_target
  puts "== Creating HomeWidgetExtension target =="
  widget_target = project.new_target(
    :app_extension,
    'HomeWidgetExtension',
    :ios,
    '17.0'
  )

  # Place build product next to other extensions
  widget_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'ru.recipescaler.RecipeScalerNative.HomeWidget'
    config.build_settings['PRODUCT_NAME'] = 'HomeWidgetExtension'
    config.build_settings['MARKETING_VERSION'] = '1.0'
    config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
    config.build_settings['SWIFT_VERSION'] = '5.9'
    config.build_settings['DEVELOPMENT_TEAM'] = '2L5JDYE2L7'
    config.build_settings['CODE_SIGN_IDENTITY'] = 'iPhone Developer'
    config.build_settings['INFOPLIST_FILE'] = 'HomeWidgetExtension/Info.plist'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['SKIP_INSTALL'] = 'YES'
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
    config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks'
    ]
  end
  apply_widget_build_settings(widget_target)
  puts "  Created target: #{widget_target.name}"

  # App extension dependency from the host app + embed in "Embed App Extensions"
  embed_phase = app_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
  unless embed_phase
    embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
    embed_phase.dst_subfolder_spec = 13
    puts "  Created Embed App Extensions phase"
  end
  widget_ref = widget_target.product_reference
  # Avoid duplicate entries in the embed phase
  already_embedded = embed_phase.files_references.any? { |r| r.path == widget_ref.path }
  unless already_embedded
    embed_phase.add_file_reference(widget_ref, true)
  end
  app_target.add_dependency(widget_target)
  puts "  Wired app dependency + embed"
else
  apply_widget_build_settings(widget_target)
end

remove_entitlements_copy_phase(widget_target)
cleanup_widget_build_phases(widget_target, core_target.product_reference)

# --- Wire RecipeScalerCore: Snapshots subgroup + files ---
core_group = project.main_group.find_subpath('RecipeScalerCore', false)
abort 'RecipeScalerCore group not found' unless core_group

snapshots_group = core_group.children.find { |c| c.respond_to?(:path) && c.path == 'Snapshots' }
unless snapshots_group
  snapshots_group = core_group.new_group('Snapshots', 'Snapshots')
  puts "== Created Snapshots subgroup =="
end

puts "\n== RecipeScalerCore: AppGroup.swift (shared constant) =="
add_swift_file(core_group, core_target, 'AppGroup.swift', 'AppGroup.swift')

puts "\n== RecipeScalerCore: Snapshots =="
# Group path is 'Snapshots', so file rel paths are bare filenames.
add_swift_file(snapshots_group, core_target, 'TimerSnapshot.swift',     'TimerSnapshot.swift')
add_swift_file(snapshots_group, core_target, 'TimerSnapshotStore.swift', 'TimerSnapshotStore.swift')
add_swift_file(snapshots_group, core_target, 'TimerWidgetKind.swift',   'TimerWidgetKind.swift')

puts "\n== HomeWidgetExtension: source files =="
# Group for the extension (path = HomeWidgetExtension)
widget_group = project.main_group.find_subpath('HomeWidgetExtension', true)
# Ensure the group has the right path
widget_group.set_path('HomeWidgetExtension') if widget_group.path.nil?
ensure_group_file(widget_group, 'HomeWidgetExtension.entitlements', 'text.plist.entitlements')
ensure_group_file(widget_group, 'Info.plist', 'text.plist.xml')
[
  'HomeWidgetBundle.swift',
  'TimerWidget.swift',
  'TimerWidgetProvider.swift',
  'TimerWidgetEntry.swift',
].each do |f|
  add_swift_file(widget_group, widget_target, f, f)
end

# Views subgroup (path = Views, nested under HomeWidgetExtension)
views_group = widget_group.children.find { |c| c.respond_to?(:path) && c.path == 'Views' }
unless views_group
  views_group = widget_group.new_group('Views', 'Views')
end
[
  'TimerHomeSmallView.swift',
  'TimerAccessoryCircularView.swift',
  'TimerAccessoryRectangularView.swift',
  'TimerAccessoryInlineView.swift',
  'WidgetTimerAccent.swift',
  'WidgetTimerBackground.swift',
  'WidgetFonts.swift',
  'WidgetTimerLayout.swift',
  'WidgetTimerPalette.swift',
  'WidgetTimerFormatting.swift',
  'WidgetTimerRing.swift',
  'WidgetTimerLinearRow.swift',
].each do |f|
  add_swift_file(views_group, widget_target, f, f)
end

puts "\n== HomeWidgetExtension: link RecipeScalerCore.framework =="
core_product = core_target.product_reference
if core_product
  linked = widget_target.frameworks_build_phase.files.any? do |bf|
    bf.file_ref == core_product
  end
  if linked
    puts "  [skip] RecipeScalerCore.framework already linked"
  else
    widget_target.frameworks_build_phase.add_file_reference(core_product)
    puts "  [add] RecipeScalerCore.framework -> HomeWidgetExtension Frameworks"
  end
  # Remove mistaken Resources entries (from older wire runs).
  widget_target.resources_build_phase.files
    .select { |bf| bf.file_ref == core_product }
    .each(&:remove_from_project)
else
  puts "  [warn] Could not find RecipeScalerCore product reference"
end

existing_dep = widget_target.dependencies.find { |d| d.target == core_target }
unless existing_dep
  widget_target.add_dependency(core_target)
  puts "  [add] HomeWidgetExtension -> RecipeScalerCore dependency"
else
  puts "  [skip] HomeWidgetExtension -> RecipeScalerCore dependency exists"
end

puts "\n== HomeWidgetExtension: fonts + Localizable.xcstrings =="
%w[
  MartianGrotesk-NrLt.otf
  MartianGrotesk-NrMd.otf
  MartianMono-NrLt.otf
].each do |font|
  ref = project.files.find { |f| f.path == font }
  add_resource_ref(widget_target, ref, font)
end

existing_resource = widget_target.resources_build_phase.files.find do |bf|
  bf.file_ref && bf.file_ref.real_path.to_s.end_with?('Localizable.xcstrings')
end
if existing_resource
  puts "  [skip] Localizable.xcstrings already in Resources"
else
  ref = project.main_group.find_subpath('Resources/Resources/Localizable.xcstrings', false)
  add_resource_ref(widget_target, ref, 'Localizable.xcstrings')
end

puts "\n== RecipeScalerNative: TimerSnapshot+RecipeTimer =="
live_activity_group = project.main_group.find_subpath('RecipeScalerNative/LiveActivity', false)
target_group = live_activity_group || app_target
add_swift_file(target_group, app_target, 'TimerSnapshot+RecipeTimer.swift', 'TimerSnapshot+RecipeTimer.swift')

project.save
puts "\nSaved #{PROJECT_PATH}"
