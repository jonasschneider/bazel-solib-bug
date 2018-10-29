cc_library(
	name = "appcode",
	srcs = ["dummy.c"],
)

cc_binary(
	name = "libplugin.so",
	srcs = ["appcode"],
	linkshared = True,
	visibility = ["//visibility:public"],
)
