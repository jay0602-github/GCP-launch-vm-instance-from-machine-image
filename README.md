# 📌 ** Script 1**

## **launch_dr_vm_same_project.sh**

### Purpose

This script launches a **Disaster Recovery (DR) VM from a machine image within the same project**, but in a **different region** (e.g., Mumbai → Delhi).
Useful for **DR drills, region failover, and multi-region resiliency**.

---

### When to use

Use Script-1 when:

* Source project and destination project are **same**
* VM must be launched in **another region of the same project**
* VM must be launched using **CMEK (Custom KMS encryption)**
* Network is hosted in a **Shared VPC host project**

---

### Required input details

| Input               | Example                                           |
| ------------------- | ------------------------------------------------- |
| Project ID          | prod-prj-psb59-svc                                |
| Machine Image Name  | prod-psb59-app-server-gcp-1a-backup-20251118-2030 |
| Host VPC Project ID | prod-prj-host-nw                                  |
| Network Name        | prod-vpc-gcp-opl                                  |

Other values (region, zone, subnet, KMS key, service account) are selected automatically via menus.

---

### What the script does automatically

✔ Lists India regions → user selects
✔ Lists zones in selected region → user selects
✔ Lists **only private subnets** from Shared VPC → user selects
✔ Lists available **CMEK encryption keys** → user selects
✔ Lists service accounts → user selects
✔ Adds **no external IP automatically** → secure DR launch
✔ Creates VM using selected machine image

---

### Example expected successful output

```
🎉 SUCCESS — DR VM Created
VM: prod-psb59-app-server-dr-1a  |  Region: asia-south2  |  Zone: asia-south2-a
```

---

### Preconditions

| Requirement                              | Status |
| ---------------------------------------- | ------ |
| Machine image exists                     | Yes    |
| Subnet exists in chosen region           | Yes    |
| CMEK key exists in chosen region         | Yes    |
| DR service account has encryption access | Yes    |

No IAM sharing required between projects (because source and dest are same).

---

### Command to run

```bash
chmod +x launch_dr_vm_same_project.sh
./launch_dr_vm_same_project.sh
```

---

<br>

# 📌 **Script 2**

## **launch_dr_vm_cross_project.sh**

### Purpose

This script launches a **VM in a different project** using a **machine image from another project**.
Example: **SIT → QA** / **QA → UAT** / **UAT → PROD** / **PROD → DR**.

---

### When to use

Use Script-2 when:

* Source and destination projects are **different**
* Machine image is created in **Project-A**
* VM must be launched in **Project-B**
* VM must use **Destination KMS encryption (CMEK)**

---

### Required input details

| Input                  | Example                                               |
| ---------------------- | ----------------------------------------------------- |
| Source Project ID      | dev-prj-gst-svc-sit                                   |
| Destination Project ID | dev-prj-gst-svc-qa                                    |
| Machine Image Name     | sit-bob-gst-sahay-app-server-gcp-backup-20250708-2030 |
| Host VPC Project ID    | dev-prj-host-nw                                       |
| Network Name           | dev-vpc-gcp-opl                                       |

Other values (region, zone, subnet, KMS key, service account) are selected automatically via menus.

---

### What the script does automatically

✔ Pulls zones from **destination project**
✔ Pulls **private subnets** from Shared VPC
✔ Pulls **CMEK keys only from destination project**
✔ Pulls **service accounts only from destination project**
✔ Launches instance **without public IP**

---

### Cross-Project IAM Requirement (Mandatory)

Before using Script-2, run this **only once per source–destination project pair**:

```
gcloud projects add-iam-policy-binding <SOURCE_PROJECT> \
  --member=serviceAccount:<DEST_PROJECT_NUMBER>@cloudservices.gserviceaccount.com \
  --role=roles/compute.imageUser
```

If this step is missing, VM launch will fail with:

```
ERROR: Read access to image denied
```

---

### Example expected successful output

```
🎉 SUCCESS — Cross-Project DR VM Created
VM: sit-pabl-java-mig-app-server-gcp | Project: dev-prj-pabl-svc-uat | Region: asia-south1 | Zone: asia-south1-b
```

---

### Command to run

```bash
chmod +x launch_dr_vm_cross_project.sh
./launch_dr_vm_cross_project.sh
```

---

<br>

## 🔚 Final Comparison Summary

| Feature                     | Script 1 | Script 2               |
| --------------------------- | -------- | ---------------------- |
| Launch in same project      | ✔        | ✖                      |
| Launch in different project | ✖        | ✔                      |
| CMEK encryption             | ✔        | ✔                      |
| No public IP                | ✔        | ✔                      |
| Shared VPC support          | ✔        | ✔                      |
| Needs IAM binding           | ✖        | ✔ (only once per pair) |

---

