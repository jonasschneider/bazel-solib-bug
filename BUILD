exports_files(["main.sh"])

sh_binary(
	name = "main",
	srcs = ["main.sh"],
	data = ["@child//:libplugin.so"],
)
