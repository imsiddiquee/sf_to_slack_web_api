import { LightningElement, track } from 'lwc';
import getUploadUrl from '@salesforce/apex/SlackFileUploadController2.getUploadUrl';
import uploadFileToSlack from '@salesforce/apex/SlackFileUploadController2.uploadFileToSlack';
import completeUpload from '@salesforce/apex/SlackFileUploadController2.completeUpload';
import retriveChannels from '@salesforce/apex/SlackFileUploadController2.retriveChannels';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class LwcFileUploader extends LightningElement {
    @track file;
    @track fileInfo;
    @track message = '';
    @track loading = false;
    @track channelDataList=[];
    @track selectedChannel;

    get uploadDisabled() {
        // console.log('this.selectedChannel-->',JSON.stringify(this.selectedChannel));
        // console.log('this.file-->',JSON.stringify(this.file));
        return (!this.file || !this.selectedChannel);
    }

    connectedCallback()
    {
        this.fetchChannels();
    }

    fetchChannels(){
        retriveChannels().then(response=>{
            console.log('channel list-->',JSON.stringify(response));
            this.formatChannelsData(response.channels)
        }).catch(error=>{
            console.error(error);
        })
    }

    formatChannelsData(res){
        this.channelDataList = res.map((item, index)=>{
            let value = item.id;            
            let label = item.name;
            return {value: value, label: label}
        })

    }

    handleChange(event)
    {
        this.selectedChannel = event.detail.value;
        console.log(event.detail.value);
    }

    handleFileChange(event) {
        this.file = event.target.files[0];
        if (this.file) {
            this.fileInfo = {
                name: this.file.name,
                size: this.file.size
            };
        } else {
            this.fileInfo = null;
        }
    }

    handleClear() {
        this.file = null;
        this.fileInfo = null;
        this.selectedChannel=null;        
        this.template.querySelector('lightning-combobox[data-id="slackChannelList"]').value='';
        this.template.querySelector('[data-id="message"]').value='';
    }

    async handleUpload() {
        try {
            this.loading = true;
            const filename = this.file.name;
            const length = this.file.size;

            // Step 1: Get the upload URL from Slack
            const uploadUrlResponse = await getUploadUrl({ filename, length });
            const uploadInfo = JSON.parse(uploadUrlResponse);
            const uploadUrl = uploadInfo.uploadUrl;
            const fileId = uploadInfo.fileId;

            // Step 2: Upload the file to the obtained URL via Apex controller
            const fileReader = new FileReader();
            fileReader.onload = async () => {
                const fileData = fileReader.result.split(',')[1]; // Base64-encoded string
                await uploadFileToSlack({ uploadUrl, fileBase64: fileData, filename });

                const textAreaMessage = this.template.querySelector('[data-id="message"]').value;
                //console.log('textAreaMessage-->',textAreaMessage);
                
                // Step 3: Complete the upload
                await completeUpload({ fileId,slackMessage:textAreaMessage,selectedChannel: this.selectedChannel });

                // Notify the user of success
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'File uploaded to Slack successfully!',
                        variant: 'success'
                    })
                );

                // Reset file and message
               this.handleClear();
            };
            fileReader.readAsDataURL(this.file);
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }
}
