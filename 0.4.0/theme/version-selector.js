(function () {
  var pathSegments = window.location.pathname.split("/").filter(Boolean);

  // GitHub project pages: /<repo-name>/<version>/path...
  // Custom domain: /<version>/path...
  var repoName = "ongeul";
  var versionIndex = 0;
  if (pathSegments[0] === repoName) {
    versionIndex = 1;
  }

  var currentVersion = pathSegments[versionIndex] || "dev";
  var basePath = "/" + pathSegments.slice(0, versionIndex).join("/");
  if (basePath.length > 1) basePath += "/";

  var innerPath = pathSegments.slice(versionIndex + 1).join("/");

  fetch(basePath + "versions.json")
    .then(function (r) {
      return r.json();
    })
    .then(function (versions) {
      var allVersions = ["dev"].concat(versions);

      var select = document.createElement("select");
      select.id = "version-selector";
      select.setAttribute("aria-label", "문서 버전 선택");

      allVersions.forEach(function (v) {
        var option = document.createElement("option");
        option.value = v;
        option.textContent = v === "dev" ? "dev (개발)" : "v" + v;
        if (v === currentVersion) option.selected = true;
        select.appendChild(option);
      });

      select.addEventListener("change", function () {
        window.location.href = basePath + this.value + "/" + innerPath;
      });

      var rightButtons = document.querySelector(".right-buttons");
      if (rightButtons) {
        var wrapper = document.createElement("div");
        wrapper.className = "version-selector-wrapper";
        wrapper.appendChild(select);
        rightButtons.insertBefore(wrapper, rightButtons.firstChild);
      }
    })
    .catch(function () {
      // versions.json이 없으면 (첫 배포 전) 셀렉터를 표시하지 않음
    });
})();
