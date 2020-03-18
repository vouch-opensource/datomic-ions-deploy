# Datomic Ions Deploy
A Github action to deploy [Datomic Ions](https://docs.datomic.com/cloud/ions/ions.html) to [Datomic Cloud](https://www.datomic.com/).

The action is based on a [Docker container](https://hub.docker.com/repository/docker/vouchio/clj-jdk8-alpine) that has Clojure installed over `adoptopenjdk/openjdk8:alpine-slim`

The action will use the checked out version of the code to
1. Verify if the current version is already deployed to the specified compute group
2. Push and deploy this version if it isn't already installed
3. Wait until deployment is successful

Note: Since the action is not interactive, it invokes the CLI via `clojure` rather than `clj`. This distinction should usually be unimportant and is mentioned here for completeness.

## Inputs

### `alias`

**Optional:** The tools.deps alias that runs -m datomic.ion.dev

**Default:** `:ion-dev`

### `compute-group`

**Required:** The compute group to which the ions should be deployed

### `ssh-key`

**Optional:** A GitHub secret that has the The SSH key needed to access code from other private repositories (eg `${{ secrets.SSH_PRIVATE_KEY }}`)

**Default:** no SSH agent is started or key used

#### Why an SSH key?
When running this action clojure tools.deps might need to fetch dependencies from your other private repositories, which uses the ssh-agent to authenticate.

GitHub Actions only have access to the repository they run for. To access additional private repositories you need to provide an SSH key with sufficient access privileges.

_Please note that there are some other actions on the GitHub marketplace that enable setting up an SSH agent. Our experience is that the mechanisms to support SSH agent interplay between actions is complex and complexity brings risks. We think that it is more straightforward and secure to have this action support the feature within its own scope. We will continue to review this choice as the Docker options improve and the GitHub environment matures._

**For security purposes, we do not expose the SSH agent outside of this action.**

#### SSH Setup
1. Create an SSH key with sufficient access privileges. For security reasons, don't use your personal SSH key but set up a dedicated one for use in GitHub Actions. See the [Github documentation](https://developer.github.com/v3/guides/managing-deploy-keys/) for more support.
1. Make sure you **don't have a passphrase** set on the private key.
1. In your repository, go to the _Settings > Secrets_ menu and create a new secret. In this example, we'll call it `SSH_PRIVATE_KEY`. Put the contents of the private SSH key file into the contents field.
1. This key must start with `-----BEGIN ... PRIVATE KEY-----`, consist of many lines and ends with `-----END ... PRIVATE KEY-----`.

### `aws-region`

**Required**: The AWS region of your datomic cloud system

### `aws-access-key-id`

**Required**: The AWS_ACCESS_KEY_ID to use for authentication

### `aws-secret-access-key`

**Required**: The AWS_SECRET_ACCESS_KEY to use for authentication

#### AWS IAM permissions

Make sure that the AWS access keys you are providing to the action have an IAM policy containing at least the following permissions.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PushToCodeDeploy",
            "Effect": "Allow",
            "Action": [
                "codedeploy:ListDeploymentGroups",
                "codedeploy:RegisterApplicationRevision"
            ],
            "Resource": "arn:aws:codedeploy:<region>:<account>:application:<ion-application>"
        },
        {
            "Sid": "RetrieveStackInformation",
            "Effect": "Allow",
            "Action": [
                "cloudformation:DescribeStacks"
            ],
            "Resource": [
                "arn:aws:cloudformation:<region>:<account>:stack/<compute-group>/*"
            ]
        },
        {
            "Sid": "CreateIonLambda",
            "Effect": "Allow",
            "Action": [
                "lambda:GetFunction",
                "lambda:CreateFunction"
            ],
            "Resource": [
                "arn:aws:lambda:<region>:<account>:function:<compute-group>-*"
            ]
        },
        {
            "Sid": "TriggerStepFunction",
            "Effect": "Allow",
            "Action": [
                "states:StartExecution",
                "states:DescribeExecution"
            ],
            "Resource": [
                "arn:aws:states:<region>:<account>:stateMachine:datomic-<compute-group>",
                "arn:aws:states:<region>:<account>:execution:datomic-<compute-group>:*"
            ]
        },
        {
            "Sid": "CheckDeployStatus",
            "Effect": "Allow",
            "Action": [
                "states:DescribeExecution",
                "states:GetExecutionHistory"
            ],
            "Resource": [
                "arn:aws:states:<region>:<account>:execution:datomic-<compute-group>:*"
            ]
        },
        {
            "Sid": "RetrieveDeploymentInformation",
            "Effect": "Allow",
            "Action": [
                "codedeploy:ListDeployments",
                "codedeploy:GetDeployment"
            ],
            "Resource": [
                "arn:aws:codedeploy:<region>:<account>:deploymentgroup:<application>/<compute-group>"
            ]
        },
        {
            "Sid": "DatomicS3BucketAccess",
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "arn:aws:s3:::datomic-releases-1fc2183a",
                "arn:aws:s3:::datomic-releases-1fc2183a/*",
                "arn:aws:s3:::datomic-code-<your-code-bucket-uuid>",
                "arn:aws:s3:::datomic-code-<your-code-bucket-uuid>/*"
            ]
        }
    ]
}
```

### `working-directory`

**Optional**: Directory containing the ions code

**Default**: `./`

## Example usage

### default, to run `:ion-dev` alias

```yaml 
- name: Deploy Datomic ions
  uses: actions/datomic-ions-deploy@v0.1.0
  with:
    compute-group: ${{ env.DATOMIC_COMPUTE_GROUP }}
    aws-region: ${{ env.AWS_REGION }}
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### with SSH Key

When you need to fetch private gitlibs with tools.deps, use `ssh-key`

```yaml 
- name: Deploy Datomic ions
  uses: actions/datomic-ions-deploy@v0.1.0
  with:
    compute-group: ${{ env.DATOMIC_COMPUTE_GROUP }}
    aws-region: ${{ env.AWS_REGION }}
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    ssh-key: ${{ secrets.SSH_KEY }}
```

### with an alternative alias

```yaml 
- name: Deploy Datomic ions
  uses: actions/datomic-ions-deploy@v0.1.0
  with:
    alias: :dev
    compute-group: ${{ env.DATOMIC_COMPUTE_GROUP }}
    aws-region: ${{ env.AWS_REGION }}
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### with a different working directory

In case you want to use this action in a repository that has the ions code in a directory other than the root, 
use the `working-dir` parameter. 

Another use case might be that you have a github workflow that needs to run tests against a specific version of
the ions code that is stored in another repository.

```yaml 
- uses: actions/checkout@v2

# Checkout the ions code from another repository
- name: Checkout vzp-datomic
  uses: actions/checkout@v2
  with:
    repository: 'your-org/my-ions-repo'
    path: my-ions-repo
    ref: master

# Now deploy the ions
- name: Deploy Datomic ions
  uses: actions/datomic-ions-deploy@v0.1.0
  with:
    compute-group: ${{ env.DATOMIC_COMPUTE_GROUP }}
    working-dir: my-ions-repo
    aws-region: ${{ env.AWS_REGION }}
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

... execute tests ...
```

# License
The scripts and documentation in this project are released under the [MIT License](LICENSE)

