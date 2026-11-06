--[[----------------------------------------------------------------------------
Info.lua — manifest for the Vault Photos Lightroom Classic publish service.
------------------------------------------------------------------------------]]

return {

	LrSdkVersion = 13.0,
	LrSdkMinimumVersion = 10.0,

	LrToolkitIdentifier = 'com.garyburd.vaultphotos',
	LrPluginName = 'vaultphotos',

	LrExportServiceProvider = {
		title = 'Vault Photos',
		file = 'PublishServiceProvider.lua',
	},

	VERSION = { major = 0, minor = 1, revision = 0, build = 0 },

}
