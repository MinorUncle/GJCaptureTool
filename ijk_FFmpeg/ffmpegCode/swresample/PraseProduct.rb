#!/usr/bin/ruby -w

#  PraseProduct.rb
#  Mp4v2Code
#
#  Created by 未成年大叔 on 16/10/21.
#  Copyright © 2016年 MinorUncle. All rights reserved.

require 'xcodeproj'

groupName = ARGV[0]
targetName = ARGV[1]
project_path = ARGV[2]
staticFile_path = ARGV[3]

def getFileRef(pGroup,fileName)
    fRef = pGroup.find_file_by_path(fileName)
    if fRef == nil
        for child in pGroup.groups
            fRef = getFileRef(child,fileName)
            if fRef != nil
                break
            end
        end
    end
    fRef
end



def clearTarget(pTarget)
    pTarget.resources_build_phase.clear
    puts "clear target"
end




project = Xcodeproj::Project.open(project_path)
puts "project_path:#{project_path} project:#{project}"

targets = project.targets
for target in targets
    if target.name == targetName
        break;
    end
end
puts "targetName:#{targetName}  targets:#{targets}  target:#{target} gropName:#{groupName}"
group = project.main_group.find_subpath(groupName, false)
puts "group:#{group.path} groupName:#{groupName}"

clearTarget(target);

addArry = Array.new()

IO.foreach(staticFile_path){|block|
    block[".o"]=".c"
    block.rstrip!
    fRef = getFileRef(group,block)
    puts "file:#{fRef},name:#{block}"
    if fRef != nil
        addArry.push(fRef)
    end
}
puts "add_file_referencesfile:#{addArry.length} #{addArry.class}"
target.add_file_references(addArry)
puts "file:#{addArry.length}"
project.save

