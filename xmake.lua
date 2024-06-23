set_project("autumnbot")
set_version("0.0.1")

add_rules("mode.debug", "mode.release")
add_rules("plugin.compile_commands.autoupdate", {outputdir = "."})

add_requires("spdlog", "nlohmann_json")

target("autumnbot")
    set_kind("binary")
    set_languages("c++20")
    set_toolchains("clang")
    
    add_includedirs("src")
    add_files("src/*.cpp", "src/**/*.cpp")
    add_cxxflags("clang::-stdlib=libc++")
    add_packages("spdlog", "nlohmann_json")
    add_ldflags("-lc++")
    add_links("opencv_core", "opencv_videoio", "opencv_highgui", "opencv_imgproc", "opencv_imgcodecs", "opencv_plot")

    after_build(function (target)
        import("core.project.project")
        import("core.base.task")
        
        task.run("project", {kind = "cmake", outputdir = "."})
        task.run("project", {kind = "ninja", outputdir = "."})
        task.run("project", {kind = "makefile", outputdir = "."})
    end)