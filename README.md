# tank-aws

* `terraform init`
* `terraform apply` - Could take a while due kubernetes cluster creating
* Download the latest release: https://github.com/kubernetes-sigs/aws-iam-authenticator/releases
* Add `aws-iam-authenticator` binary to `$PATH`
* `kubectl --kubeconfig=kubeconfig apply -f confi_map_auth.yml`
* `kubectl --kubeconfig=kubeconfig get nodes`

### Hints

* Helps to build suitable `kubeconfig` file: `aws --region <region> eks update-kubeconfig --name <cluster-name> --role-arn <eks-role>`
* One easy way to communicate with EKS Clusters is https://eksctl.io/