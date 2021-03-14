Pod::Spec.new do |s|
    s.name                  = 'OBD2Connect'
    s.module_name           = 'OBD2Connect'

    s.version               = '2.2.0'

    s.homepage              = 'https://github.com/Wisors/OBD2Connect'
    s.summary               = 'A simple component that handles socket connection to OBD2 adapters.'

    s.author                = { 'Nikishin Alexander' => 'wisdoomer@gmail.com' }
    s.license               = { :type => 'MIT', :file => 'LICENSE' }
    s.platforms             = { :ios => '9.0' }
    s.ios.deployment_target = '9.0'
    s.swift_versions        = '5.0'

    s.source_files          = 'Sources/*.swift'
    s.source                = { :git => 'https://github.com/Wisors/OBD2Connect.git', :tag => s.version }
end
