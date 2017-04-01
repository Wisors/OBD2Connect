Pod::Spec.new do |s|
    s.name                  = 'OBD2Connect'
    s.module_name           = 'OBD2Connect'

    s.version               = '1.2.1'

    s.homepage              = 'https://github.com/Wisors/OBD2Connect'
    s.summary               = 'A simple component that handles connection to a OBD2 adapter via socket.'

    s.author                = { 'Nikishin Alexander' => 'wisdoomer@gmail.com' }
    s.license               = { :type => 'MIT', :file => 'LICENSE' }
    s.platforms             = { :ios => '8.0' }
    s.ios.deployment_target = '8.0'

    s.source_files          = 'Sources/*.swift'
    s.source                = { :git => 'https://github.com/Wisors/OBD2Connect.git', :tag => s.version }
end
