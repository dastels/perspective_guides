#!/usr/local/bin/ruby

require 'prawn'
require 'json'
require 'slop'

include Prawn::Measurements

def float?(s)
  s.to_f > 0
end


def integer?(s)
  s.to_i > 0
end

def process_args
  cmdline_config = {}

  opts = Slop.parse(banner: "usage: #{$0} [options] specification-file") do |o|
    o.string '-f', '--file', 'output filename, if not specified the input filename is used with the suffix changed to pdf'
    o.string '-p', '--page-size', 'page size, either a standard size (eg. A4) or <width>x<height> in mm or in (eg. 9inx12in) (default A4)', default: 'A4'
    o.integer '-h', '--horizon', 'how far up is the horizon line... in % of page height (default 50)', default: 50
    o.integer '-1', '--vp1', 'position of the lefthand vanishing point... in % from center to left edge (can be > 100) (default none)', default: nil
    o.integer '-2', '--vp2', 'position of the righthand vanishing point... in % from center to right edge (can be > 100) (default none)', default: nil
    o.integer '-a', '--angle', 'angle increment of lines from each vanishing point (defalt 30)', default: 30
    o.string '-c', '--colour', 'colour of the graph lines (default DDDDDD)', default: '000000'
    o.string '-o', '--orientation', 'portrait or landscape, not valid with custom widthxheight page size (default: landscape)', default: 'landscape'
    o.separator ''
    o.separator 'other options:'
    o.bool '-v', '--verbose', 'show informational output', default: false
    o.on '--version', 'print the version number' do
      puts "0.0.1"
      exit
    end
    o.on '-?', '--help', 'print options' do
      puts o
      exit
    end
  end


  [:page_size, :horizon, :vp1, :vp2, :angle, :colour, :orientation].each do |k|
    cmdline_config[k] = opts[k] unless opts[k].nil?
  end

  return cmdline_config, opts[:file], opts[:verbose]
end

$config, output_filename, $verbose = process_args


puts $config if $verbose

# compute the page dimensions
if PDF::Core::PageGeometry::SIZES.include?($config[:page_size])
  page_size = PDF::Core::PageGeometry::SIZES[$config[:page_size]]
  case $config[:orientation]
  when 'portrait'
    width_pt = page_size[0]
    height_pt = page_size[1]
  when 'landscape'
    width_pt = page_size[1]
    height_pt = page_size[0]
  else
    puts "Bad orientation: #{$config[:orientation]}"
    exit
  end
else
  matches = $config[:page_size].match(/(\d+)(in|mm)?[xX](\d+)(in|mm)?/)
  if matches.nil?
    puts "Bad page size: #{$config[:page_size]}"
    exit
  else
    width = matches[1].to_i
    width_unit = matches[2]
    height = matches[3].to_i
    height_unit = matches[4]
    puts "page size: #{width}#{width_unit} x #{height}#{height_unit}" if $verbose
    width_pt = width_unit == 'in' ? in2pt(width) : mm2pt(width)
    height_pt = height_unit == 'in' ? in2pt(height) : mm2pt(height)
  end
end

half_x = width_pt / 2.0
half_x_less_border = half_x - 10

# validate vanishing points
if $config[:vp1].nil? && $config[:vp2].nil?
    puts "Must supply at least one vanishing point"
    exit
end

one_point = $config[:vp1].nil? || $config[:vp2].nil?

# compute vanishing points
vanishing_point_1 = $config[:vp1].nil? ? nil : half_x - (half_x_less_border * $config[:vp1]) / 100
vanishing_point_2 = $config[:vp2].nil? ? nil : half_x + (half_x_less_border * $config[:vp2]) / 100

# adjust if only VP2 specified
if vanishing_point_1.nil?
  vanishing_point_1 = vanishing_point_2
  vanishing_point_2 = nil
end



# OK now make the page

pdf = Prawn::Document.new(page_size: [width_pt, height_pt], margin: 0)
pdf.stroke_color($config[:colour])
pdf.fill_color($config[:colour])


def deg2rad(deg)
  deg * 0.01745
end

def rad2deg(rad)
  rad / 0.01745
end

angle = deg2rad($config[:angle])
horizon = (height_pt * $config[:horizon].to_f) / 100.0

if $verbose
  puts "Width: #{width_pt}"
  puts "Height: #{height_pt}"
  puts "Horizon: #{horizon}"
  puts "#{one_point ? 'one' : 'two'} point perspective"
  puts "VP1: #{$config[:vp1]} left of center - #{vanishing_point_1}"
  puts "VP2: #{$config[:vp2]} left of center - #{vanishing_point_2}" unless one_point
  puts "angle: #{$config[:angle]} deg"
  puts "#{(deg2rad(360) / angle).floor} lines"
end



# Draw the perspective lines

def draw_line(pdf, i, horizon, vp, x, y)
  puts "Line #{i} from (#{vp}, #{horizon}) to (#{x}, #{y})" if $verbose
  pdf.stroke do
    pdf.move_to(vp, horizon)
    pdf.line_to(x, y)
  end
end

def draw_lines(pdf, vpname, vp, horizon, angle, height_pt, width_pt)
  puts "Drawing lines for #{vpname}" if $verbose
  bottom = horizon
  top = height_pt - bottom
  left = vp
  right = width_pt - left

  if $verbose
    puts "top: #{top}"
    puts "bottom: #{bottom}"
    puts "left: #{left}"
    puts "right: #{right}"
    puts "\n\n"
  end

  off_left = left < 0
  off_right = right < 0

  if $verbose
    puts "Off left: #{off_left}"
    puts "Off right: #{off_right}"
    puts "\n\n"
  end

  angles = [Math.atan(top / right.abs),    # 0
            Math.atan(right.abs / top),    # 1
            Math.atan(left.abs / top),     # 2
            Math.atan(top / left.abs),     # 3
            Math.atan(bottom / left.abs),  # 4
            Math.atan(left.abs / bottom),  # 5
            Math.atan(right.abs / bottom), # 6
            Math.atan(bottom / right.abs)] # 7
  if $verbose
    puts "#{vpname} angles:"
    angles.each {|a| puts "#{a} - #{rad2deg(a)}" }
    puts "\n\n"
  end

  angle_sums = []
  angle_sums << angles[0]
  angle_sums << angle_sums[0] + angles[1]
  angle_sums << angle_sums[1] + angles[2]
  angle_sums << angle_sums[2] + angles[3]
  angle_sums << angle_sums[3] + angles[4]
  angle_sums << angle_sums[4] + angles[5]
  angle_sums << angle_sums[5] + angles[6]
  angle_sums << angle_sums[6] + angles[7]
  if $verbose
    puts "#{vpname} sum of angles:"
    angle_sums.each {|a| puts "#{a} - #{rad2deg(a)}" }
    puts "\n\n"
  end

  number_of_lines = (deg2rad(360) / angle).floor

  (1...number_of_lines).each do |i|
    line_angle = i * angle
    puts "Angle: #{rad2deg(line_angle)}"
    case line_angle
    when 0...angle_sums[0]             # 1
      unless off_right
        puts "case 1" if $verbose
        draw_line(pdf, i, horizon, vp, width_pt, bottom + (right * Math.tan(line_angle)))
      end
    when angle_sums[0]...angle_sums[1] # 2
      unless off_right
        puts "case 2" if $verbose
        draw_line(pdf, i, horizon, vp, vp + (top * Math.tan(angle_sums[1] - line_angle)), height_pt)
      end
    when angle_sums[1]...angle_sums[2] # 3
      unless off_left
        puts "case 3" if $verbose
        draw_line(pdf, i, horizon, vp, vp - (top * Math.tan(line_angle - angle_sums[1])), height_pt)
      end
    when angle_sums[2]...angle_sums[3] # 4
      unless off_left
        puts "case 4" if $verbose
        draw_line(pdf, i, horizon, vp, 0, bottom +  (left * Math.tan(angle_sums[3] - line_angle)))
      end
    when angle_sums[3]...angle_sums[4] # 5
      unless off_left
        puts "case 5" if $verbose
        draw_line(pdf, i, horizon, vp, 0, bottom - (left * Math.tan(line_angle - angle_sums[3])))
      end
    when angle_sums[4]...angle_sums[5] # 6
      unless off_left
        puts "case 6" if $verbose
        draw_line(pdf, i, horizon, vp, vp - bottom * Math.tan(angle_sums[5] - line_angle), 0)
      end
    when angle_sums[5]...angle_sums[6] # 7
      unless off_right
        puts "case 7" if $verbose
        draw_line(pdf, i, horizon, vp, vp + (bottom * Math.tan(line_angle - angle_sums[5])), 0)
      end
    when angle_sums[6]...angle_sums[7] # 8
      unless off_right
        puts "case 8" if $verbose
        draw_line(pdf, i, horizon, vp, width_pt, bottom - right * Math.tan(angle_sums[7] - line_angle))
      end
    end

  end
end

# Draw the horizon line
pdf.stroke do
  pdf.stroke_color("FF0000")
  pdf.move_to(0, horizon)
  pdf.line_to(width_pt, horizon)
end

# Draw perspective lines
pdf.stroke_color("000000")
draw_lines(pdf, "VP1", vanishing_point_1, horizon, angle, height_pt, width_pt )
draw_lines(pdf, "VP2", vanishing_point_2, horizon, angle, height_pt, width_pt ) unless one_point

# Draw the horizon line
pdf.stroke do
  pdf.stroke_color("FF0000")
  pdf.move_to(0, horizon)
  pdf.line_to(width_pt, horizon)
end

# trim edges
pdf.fill_color("ffffff")
pdf.fill_rectangle([0, height_pt], 10, height_pt)                # left
pdf.fill_rectangle([width_pt - 10, height_pt], 10, height_pt)    # right
pdf.fill_rectangle([0, height_pt], width_pt, 10)                 # top
pdf.fill_rectangle([0, 10], width_pt, 10)  # bottom

# label it
pdf.font('Times-Roman', style: :italic)
pdf.font_size(8)
pdf.fill_color("0000FF")

pdf.stroke_color("000000")
#pdf.fill_color("ffffff")
#pdf.fill_rectangle([0, 30], width_pt, 30)
pdf.fill_color("000000")
pdf.font_size(8)
vp2_label = one_point ? '' : ", VP2: #{$config[:vp2]}% right"
pdf.text_box("Perspective guide. Horizon: #{$config[:horizon]}%, VP1: #{$config[:vp1]}% left#{vp2_label}, Angle: #{rad2deg(angle).round} deg", at: [10, 7], height: 10, width: width_pt - 20)

pdf.bounding_box([width_pt / 2, 7], width: (width_pt / 2) - 10, height: 10) do
  pdf.font('Times-Roman', style: :italic)
  pdf.text("(c) 2024 Dave Astels", align: :right)
end

# write the output file
output_file = if output_filename.nil?
                vp2_section = one_point ? '' : "-#{$config[:vp2]}"
                "#{$config[:orientation]}-#{$config[:page_size]}-#{$config[:horizon]}%-#{one_point ? 'one' : 'two'}-point-#{$config[:vp1]}#{vp2_section}-#{rad2deg(angle).round}.pdf"
              else
                output_filename
              end

puts "Writing to #{output_file}" if $verbose

pdf.render_file(output_file)
