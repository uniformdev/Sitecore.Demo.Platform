﻿using System;
using System.IO;
using System.Web.UI;
using System.Xml;

namespace Sitecore.Demo.Platform.Foundation.CoveoIndexing.Utilities
{
	public partial class ConfigureCdAndActivateCoveo : Page
	{
		protected void Page_Load(object sender, EventArgs e)
		{
			string organizationId = Request.QueryString["organizationId"];
			string apiKey = Request.QueryString["apiKey"];
			string searchApiKey = Request.QueryString["searchApiKey"];
			string farmName = Request.QueryString["farmName"];
			string adminUsername = Request.QueryString["adminUsername"];
			string adminPassword = Request.QueryString["adminPassword"];

			if (string.IsNullOrEmpty(organizationId) ||
				string.IsNullOrEmpty(apiKey) ||
				string.IsNullOrEmpty(searchApiKey) ||
				string.IsNullOrEmpty(farmName) ||
				string.IsNullOrEmpty(adminUsername) ||
				string.IsNullOrEmpty(adminPassword))
			{
				Response.Write("{ \"IsActivated\": \"false\", \"ERROR\": \"One of the query string argument is empty.\" }");
				Response.End();
				return;
			}

			bool isCoveoActivated = IsCoveoActivated();

			ConfigureCloudPlatformClientCustomFile(isCoveoActivated, organizationId, apiKey, searchApiKey);
			ConfigureSearchProviderCustomFile(isCoveoActivated, farmName, adminUsername, adminPassword);

			if (!isCoveoActivated)
			{
				Activate();
			}

			Response.Write("{ \"IsActivated\": \"true\" }");
			Response.End();
		}

		private bool IsCoveoActivated()
		{
			return File.Exists("C:\\inetpub\\wwwroot\\App_Config\\Include\\Coveo\\Coveo.SearchProvider.Custom.config");
		}

		private void ConfigureCloudPlatformClientCustomFile(bool isCoveoActivated, string organizationId, string apiKey, string searchApiKey)
		{
			string fileName = "C:\\inetpub\\wwwroot\\App_Config\\Include\\Coveo\\Coveo.CloudPlatformClient.Custom.config";
			if (!isCoveoActivated)
			{
				fileName += ".demo";
			}
			string baseXPath = "configuration/sitecore/coveo/cloudPlatformConfiguration";

			XmlDocument xmlDocument = new XmlDocument();
			xmlDocument.Load(fileName);

			xmlDocument.SelectSingleNode($"{baseXPath}/organizationId").InnerText = organizationId;
			xmlDocument.SelectSingleNode($"{baseXPath}/apiKey").InnerText = apiKey;
			xmlDocument.SelectSingleNode($"{baseXPath}/searchApiKey").InnerText = searchApiKey;

			xmlDocument.Save(fileName);
		}

		private void ConfigureSearchProviderCustomFile(bool isCoveoActivated, string farmName, string adminUsername, string adminPassword)
		{
			string fileName = "C:\\inetpub\\wwwroot\\App_Config\\Include\\Coveo\\Coveo.SearchProvider.Custom.config";
			if (!isCoveoActivated)
			{
				fileName += ".demo";
			}
			string baseXPath = "configuration/sitecore/coveo/defaultIndexConfiguration";

			XmlDocument xmlDocument = new XmlDocument();
			xmlDocument.Load(fileName);

			xmlDocument.SelectSingleNode($"{baseXPath}/farmName").InnerText = farmName;
			xmlDocument.SelectSingleNode($"{baseXPath}/sitecoreUsername").InnerText = adminUsername;
			xmlDocument.SelectSingleNode($"{baseXPath}/sitecorePassword").InnerText = adminPassword;

			xmlDocument.Save(fileName);
		}

		private void Activate()
		{
			string[] moduleFilesToRename = Directory.GetFiles("C:\\inetpub\\wwwroot\\App_Config\\Modules\\Coveo", "*.example", SearchOption.AllDirectories);
			RenameFiles(moduleFilesToRename, "example");

			string[] includeFilesToRename = Directory.GetFiles("C:\\inetpub\\wwwroot\\App_Config\\Include\\Coveo", "*.demo", SearchOption.AllDirectories);
			RenameFiles(includeFilesToRename, "demo");
		}

		private void RenameFiles(string[] filesToRename, string extension)
		{
			foreach (string fileName in filesToRename)
			{
				FileInfo fileInfo = new FileInfo(fileName);
				fileInfo.MoveTo(fileName.Replace($".config.{extension}", ".config"));
			}
		}
	}
}
